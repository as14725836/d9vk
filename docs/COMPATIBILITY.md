# 渲染问题排查：黑屏 / 偏色 / D3D10CoreCreateDevice aborting

> 适用范围：Wine + box64 环境下的 D3D8 – D3D12 游戏（本项目发布的所有 dxvk 版本）。
> 原则：先确认“到底是哪个组件在处理图形”，再改配置；不要一次改十个开关。

## 0. dx8 – dx12 的责任划分

| API | 由谁实现 | 我们的交付物 |
|---|---|---|
| D3D8 | dxvk ≥ 2.0（`d3d8.dll`） | `dxvk-2.x` / `dxvk-3.x` / `dxvk-sao-1.11.1` |
| D3D9 | dxvk（`d3d9.dll`） | 全部版本 |
| D3D10 / 10.1 | dxvk 的 `d3d10core.dll`（D3D10 的游戏直接调它） | 全部；**1.9.4 / 1.10.3 额外自带 `d3d10.dll` / `d3d10_1.dll`**；2.0 起上游已删除这两个文件 |
| D3D11 | dxvk（`d3d11.dll`） | 全部 |
| D3D12 | **不是 dxvk**，是 vkd3d-proton（`d3d12.dll` / `d3d12core.dll`） | 见 `build-vkd3d.yml` 流水线 / 上游 vkd3d-proton |

## 1. `D3D10CORE.DLL.D3D10CoreCreateDevice@20, aborting`

这条消息是 **Wine 自己的报错**（“调用了未实现函数 … aborting”），意思是：**DXVK 的 `d3d10core.dll` 没有被加载，游戏调到了 Wine 内置（stub）版本**。按出现概率排查：

1. **位数不匹配（最常见）**：32 位游戏只能用 x32 DLL。
   - 64 位 DLL → `drive_c/windows/system32`
   - 32 位 DLL → `drive_c/windows/syswow64`
   - 只装了 x64 就跑 32 位游戏 ⇒ 必然出现这条报错。
2. **装错了 WINEPREFIX**：确认 `WINEPREFIX` 指向你拷贝 DLL 的前缀。
3. **没设 DLL 覆盖**：设 `WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi=n,b"`
   （`n,b` = 优先 native、失败回退 builtin；`dxgi` 必须一起覆盖，否则交换链不走 DXVK）。
4. **游戏需要 D3D10.1**：`dxvk-2.0+` 不再提供 `d3d10_1.dll`，这类游戏请用 `dxvk-1.10.3` 或 `dxvk-1.9.4`。

自查：
```bash
WINEDEBUG=+loaddll,+module wine game.exe 2>&1 | grep -i -E 'd3d10|dxgi'
# 期望看到 Loading native module ...\\d3d10core.dll
```

## 2. 黑屏 / 只有声音 / 卡在首帧

按顺序做，每步只看一个变量：

1. 先按 §1 确认**位数、前缀、override**（半数“黑屏”其实是§1）。
2. `dxgi.deferSurfaceCreation = True`（或 `d3d9.deferSurfaceCreation = True`）
   — Android/Wayland/X 上最常见的黑屏解法。
3. 关垂直同步：`d3d9.presentInterval = 0`（或 `dxgi.syncInterval = 0`），并试**窗口化**运行。
4. 看驱动是否达标：`DXVK_HUD=devinfo`。dxvk 2.x/3.x **需要 Vulkan 1.3**；
   若驱动只到 1.1/1.2 → 退到 `dxvk-1.10.3` 或 `dxvk-sao-1.11.1`。
5. D3D10 游戏优先用 `dxvk-1.10.3`（自带 `d3d10.dll`/`d3d10_1.dll`）。
6. 采集日志而非猜：
```bash
DXVK_LOG_LEVEL=debug DXVK_LOG_PATH=./dxvk-logs DXVK_HUD=api,devinfo wine game.exe
# 生成的 dxgi.log / d3d9.log 里看 swapchain 格式、error 行
```

## 3. 画面偏黄 / 颜色不对 / 对比度异常

先二分：**是“dxvk 根本没生效”，还是“dxvk 生效但颜色错”。**

- 用 `DXVK_HUD=api`：显示 `D3D9/D3D11 (DXVK)` 才算生效；
  若显示 wined3d 或什么都不显示 → 回到 §1（override / 位数）。
- 确认生效后再调以下开关（一次一个，改完重启游戏）：

| 开关 | 适用症状 |
|---|---|
| `d3d9.forceSamplerTypeSpecConstants = True` | 贴图/颜色发灰发黑、采样类型错乱 |
| `d3d9.supportX4R4G4B4 = False` | 16 位渲染目标导致色带/偏色 |
| `d3d9.disableA8RT = True` | A8 渲染目标导致的异常颜色 |
| `d3d9.supportDFFormats = False` | DF 深度格式不被支持时的偏色/闪屏 |
| `d3d9.useD32forD24 = True` | D24 深度不被支持时 |
| `d3d9.floatEmulation = True` | 颜色/浮点表现异常（旧 GPU） |
| `d3d9.lenientClear = True` | 清屏不全导致的残影/色块 |
| `d3d9.extraFrontbuffer = True` | 画面错位/花屏（部分老游戏） |

- **驱动侧**：偏色在 Adreno/Turnip 上经常是 **WSI/颜色空间（sRGB）处理**问题，不是 DXVK。
  优先把 Turnip 升到最新（见 `docs/MESA-TURNIP-AUDIT.md`），再回来看 DXVK 开关。
- 对比基准：同一包切回 `dxvk-1.10.3` 看偏色是否消失——如果消失，则是新版本特性路径问题。

## 4. 性能与卡顿（“慢慢优化”的抓手，按收益排序）

1. **驱动**：最新 Turnip（收益最大，尤其 A7xx）。
2. **着色器编译卡顿**：`dxvk.numCompilerThreads = 2~4`；
   或直接用带 Async 的包（`dxvk-async-2.0` / `dxvk-sao-1.11.1`）并设 `dxvk.enableAsync = true`。
3. **帧率/延迟**：`dxvk.maxFrameLatency = 1`、`d3d9.presentInterval = 0`、`dxvk.tearFree = False`。
4. **内存**（32 位游戏易爆内存）：`d3d9.maxAvailableMemory`、`d3d9.textureMemory = 50~100`、`dxvk.maxMemoryBudget`。
5. **状态缓存**：玩几轮让 `state_cache` 生成完，卡顿会显著下降（跨进程保留）。
6. **新特性开关**（有风险，仅单游戏开）：`dxvk.enableDescriptorBuffer`、`dxvk.enableUnifiedImageLayouts`。

## 5. 各版本差异速查

| 包 | d3d8 | d3d9 | d3d10/10.1 | d3d10core | d3d11 | dxgi | setup_dxvk.sh |
|---|---|---|---|---|---|---|---|
| `dxvk-1.9.4` / `dxvk-1.10.3` | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `dxvk-2.0` / `dxvk-async-2.0` | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ |
| `dxvk-2.3.1` – `dxvk-3.1.1` | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | **✗（上游已删）** |
| `dxvk-sao-1.11.1` | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ |

## 6. 交换链尺寸异常（日志里出现 `Buffer size: 185x2` 这类分辨率）

日志样例：
```
info:  Presenter: Actual swap chain properties:
info:    Format:       VK_FORMAT_B8G8R8A8_UNORM
info:    Color space:  VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
info:    Present mode: VK_PRESENT_MODE_MAILBOX_KHR (dynamic: yes)
info:    Buffer size:  185x2      <-- 异常
info:    Image count:  5
```

**先搞清一件事：DXVK 不会自己发明分辨率。** 交换链尺寸就是它拿到的**窗口客户区尺寸**。
`185x2` 这种值说明创建那一刻窗口尺寸本身就是退化的（通常是窗口/虚拟显示还没协商好尺寸，
或者显示服务器报了一个极小/默认尺寸），DXVK 只是照单执行。所以这种问题**不能靠改 DLL 解决**，
要在“显示尺寸”和“枚举模式”两个环节上规避：

### 6.1 先固定尺寸，再启动游戏
- 在 Winlator / Box64 容器里**先设好显示分辨率**，不要用“跟随窗口/自动”；
- 启动顺序上，确保显示已经就绪后再拉起游戏（避免启动瞬间窗口还是0x0/极小）。

### 6.2 用固定尺寸的 Wine 虚拟桌面启动（最有效）
```bash
wine explorer /desktop=dxvk,1280x720 game.exe
# 或 1024x768 / 1280x800，按你容器分辨率选
```
虚拟桌面会把窗口固定成该尺寸，游戏拿到的客户区就不会退化，
交换链不会出现 `185x2`；同时也能避免游戏自己乱改分辨率。

### 6.3 配置兼底（放 dxvk.conf）
```ini
d3d9.forceAspectRatio = "16:9"      # 或 "4:3"，避免游戏按错误比例重设
d3d9.enumerateByDisplays = False    # 不用显示服务器枚举模式，避免拿到怪模式
d3d9.forceRefreshRate = 60          # 或 dxgi.forceRefreshRate = 60
d3d9.modeCountCompatibility = True  # 个别老游戏对模式计数敏感
```

### 6.4 不要让游戏使用“桌面分辨率”
在游戏设置里**显式选一个固定分辨率**（写进游戏的配置文件最稳），
不要选“Desktop / 当前分辨率”。

### 6.5 如果同时伴随黑屏
再按 §2 试 `dxgi.deferSurfaceCreation = True`、关 vsync（`d3d9.presentInterval = 0`）。

> 小结：`185x2` 是“窗口尺寸错了”的表现，不是 DXVK 的 bug；
> 固定虚拟桌面尺寸 + 禁用按显示枚举，基本能消除这类怪分辨率。

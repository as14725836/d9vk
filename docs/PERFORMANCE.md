# 性能与效率调优总表（Android + box64 + Wine + DXVK）

> 原则：先量后调、一次只改一项。所有键名/默认值取自 dxvk v3.1.1 官方 `dxvk.conf`；
> box64 变量名取自官方 `system/box64.box64rc`（v0.3.9 线）。

## 一、先测量

```bash
# 帧率 + 帧时间曲线（最有用）：
DXVK_HUD=fps,frametimes wine game.exe
# 设备/显存占用：
DXVK_HUD=devinfo,memory,gpuload wine game.exe
# 看游戏到底走了哪个 API（判断 DXVK 是否起作用）：
DXVK_LOG_LEVEL=info wine game.exe    # 看日志里有没有加载 d3d9.dll/d3d11.dll
```

## 二、收益从大到小（DXVK 侧）

| 项 | 默认 | 建议 | 代价 |
|---|---|---|---|
| `DXVK_STATE_CACHE_PATH`（环境变量） | 未设 | 指向可写目录 | 无（纯粹复用已编译着色器） |
| 固定虚拟桌面尺寸 | 无 | `wine explorer /desktop=dxvk,1280x720 game.exe` | 无 |
| `dxvk.maxFrameRate` | 0 | 30/60 | 无（降温、稳帧） |
| `dxvk.enableGraphicsPipelineLibrary` | Auto | True | 内存略增 |
| `dxvk.numCompilerThreads` | 0（自动） | 4~6 | 无 |
| `d3d9.deviceLocalConstantBuffers` | Auto（移动 GPU 上=关） | True | 无 |
| `dxvk.tilerMode` | Auto | True（Adreno 是 tiler） | 实测类 |
| `d3d11.relaxedBarriers` | False | True | 可能贴图错乱 |
| `dxvk.latencySleep` | Auto | False | 输入延迟略增 |
| `dxvk.maxMemoryBudget` | 0（自动） | 内存紧张时设 MB 上限 | 无 |
| `dxvk.enableMemoryDefrag` | False | True（长时段游戏） | 无 |
| `dxvk.hud` | 空 | 调试时开，平时关 | 开着会占性能 |

## 三、box64 侧（变量均见于官方 box64rc）

| 变量 | 作用 | 风险 |
|---|---|---|
| `BOX64_DYNACACHE=1` | 把翻译结果缓存到磁盘，二次启动明显更快 | 低 |
| `BOX64_DYNAREC_BIGBLOCK=3` | 更大基本块，更快 | 内存/编译时间上升 |
| `BOX64_DYNAREC_STRONGMEM=0|1` | 放宽内存序，提速 | 可能崩/花屏，数值越高越激进 |
| `BOX64_DYNAREC_SAFEFLAGS=1` | 提速 | 个别程序崩 |
| `BOX64_DYNAREC_CALLRET=1` | 调用/返回优化 | 低-中 |
| `BOX64_DYNAREC_BLEEDING_EDGE=1` | 假定支持较新指令 | 中 |
| `BOX64_MAXCPU=N` | 限线程数，减少调度抖动 | 无 |

以上已封装在 `scripts/wine-perf-launch.sh`（设 `BOX64_PERF=0` 可一键关闭）。

## 四、Wine / 系统侧

- `WINEDEBUG=-all`：关 Wine 调试输出，直接省 CPU
- `WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core=n,b"`：确保走 DXVK 而不是 Wine 内置
- 散热与续航：锁帧比任何编译选项都有效；边充电边玩会因降频更卡
- 分辨率：像素越多，Adreno 负担越大；老 galgame 用 1024x768 往往比 1080p 快得多

## 五、实测行不通的（写下来免得重复踩）

- **`-O3 -flto` 优化构建**：MinGW 交叉 + LTO 在本仓库流水线里编译失败，已放弃该变体；
  release 构建本身已是 `-O3`，LTO 是唯一额外增益，代价是不稳。
- **3.x 异步/GPU 直提补丁**：上游没有公开可用的补丁，不做逆向式修改；要异步请用 `dxvk-async-2.0` 或 `dxvk-sao-1.11.1`。
- **画面偏黄**：色彩空间/输出路径问题，换 DLL 无效；**交换链 185x2**：窗口协商问题，固定虚拟桌面解决。

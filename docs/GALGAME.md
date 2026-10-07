# Galgame / 2D 游戏在 DXVK 上的完善方案

## 0. 先分清责任边界（这步最省时间）

- DXVK 只管 **D3D8/9/10/11 → Vulkan**。
- **视频播放**（OP/ED、动态 CG）走 DirectShow / Media Foundation（Wine 的 quartz / amstream / mfplat），**换 DXVK 版本完全无用**，要装解码器或换原生 dll。
- **文字与字体**走 GDI/Uniscribe，与 DXVK 无关。
- **画面偏黄/偏色**是色彩空间与输出路径（`VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` 那一层）与容器输出配置，换 DLL 解决不了。
- 用 OpenGL/SDL 的引擎（典型是 Ren'Py）**根本不经过 DXVK**。

> 不确定某部作品走哪条路？用 `DXVK_LOG_LEVEL=info` 启动，看日志里有没有加载 `d3d9.dll` / `d3d11.dll` 就清楚了。

## 1. galgame 的典型负载特征

- 每帧大量小 draw call（背景 + 立绘 + 文字层），**常量和顶点缓冲频繁更新**；
- 分辨率低（800x600 / 1024x768），常在窗口与全屏之间切换；
- 帧率需求低（多为 30fps），但**首次出现新立绘/新特效时要编译着色器 → 卡一下**。

## 2. 按收益排序的处理

| 优先级 | 做法 | 说明 |
|---|---|---|
| 1 | 固定虚拟桌面尺寸 | 解决黑屏与 `Buffer size: 185x2` 这类退化分辨率 |
| 2 | `DXVK_STATE_CACHE_PATH` | 跨次运行复用已编译着色器，第二次启动起受益 |
| 3 | `d3d9.deviceLocalConstantBuffers = True` | 官方默认 `Auto` = **只在独显上开**，移动 GPU 上默认是关的；2D 频繁更新常量时手动开往往有收益 |
| 4 | `dxvk.enableGraphicsPipelineLibrary = True` | 减轻首次进入新场景/新立绘的编译卡顿（Turnip 支持该扩展） |
| 5 | `dxvk.maxFrameRate = 30` + `d3d9.presentInterval = 1` | 降温降耗 + 消除文字滚动撕裂 |
| 6 | `dxvk.tilerMode` / `d3d11.relaxedBarriers` | 实测类，有收益也有风险，逐项对比 |
| 7 | 关日志：`DXVK_LOG_LEVEL=none`、`WINEDEBUG=-all` | 低负载场景反而明显 |

## 3. 明确“别乱开”的项（官方文档写明是为特定游戏准备的）

- `d3d9.extraFrontbuffer`：为 Silent Hill 2 Enhanced Edition 而生，每帧多一次拷贝
- `d3d9.disableA8RT`：官方注明是为 The Sims 2
- `d3d9.cachedWriteOnlyBuffers`：官方说可能降低 GPU 受限性能（CPU 瓶颈的 2D 场景可试）
- `d3d9.forceSamplerTypeSpecConstants`：只在遇上老游戏渲染错误时才开
- `d3d9.useFP16`：2D 渐变 / alpha 混合需要精度，保持 `False`

## 4. 故障 → 开关对照

| 现象 | 先试 |
|---|---|
| 切分辨率/全屏后一直黑屏 | `dxgi.deferSurfaceCreation = True`、`d3d9.deferSurfaceCreation = True` |
| 窗口尺寸退化（185x2） | `d3d9.enumerateByDisplays = False` + 固定虚拟桌面 |
| 文字滚动撕裂/抖动 | `d3d9.presentInterval = 1`、`dxgi.syncInterval = 1` |
| 首次进新场景卡一下 | 状态缓存 + `enableGraphicsPipelineLibrary` |
| 贴图错乱/闪屏 | 把 `relaxedBarriers` 改回 `False` |
| 视频阶段黑屏 | **与 DXVK 无关**，查 quartz / mfplat / 解码器 |
| `D3D10CoreCreateDevice@20, aborting` | 位数与 override（见 `COMPATIBILITY.md`） |

## 5. 版本选型

- 首选 `dxvk-3.1.1`（2D 路径持续维护）；
- 驱动只有 Vulkan 1.1、或游戏需要 D3D10.1 → `dxvk-1.10.3`；
- 卡顿明显想试异步管线 → `dxvk-async-2.0`（注意它只到 2.0，后续版本无公开异步补丁）。

## 6. 一键用法

```bash
export DXVK_CONFIG_FILE=$PWD/dxvk.conf.galgame.example
export DXVK_STATE_CACHE_PATH=$HOME/.cache/dxvk
DXVK_HUD_VALUE=fps,frametimes ./scripts/wine-perf-launch.sh game.exe 1024x768 "$WINEPREFIX"
```

## 7. 诚实边界

- 我无法在你的设备上逐一实测每部作品：上面的组合是“先保正确性 + 只动真正相关的路径”；
  调试时建议**一次只改一项**并对比 `DXVK_HUD=fps,frametimes` 的帧时间曲线。
- 视频播放与偏色两项不在 DXVK 范围内，改 DLL 不解决问题。

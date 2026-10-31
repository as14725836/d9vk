# 本仓库的源码级补丁（不是配置）

这里的补丁直接修改 DXVK 的 C++ 代码，改变其**运行时行为**，
而不是让你去改 `dxvk.conf`。当前针对 `v3.1.1`：`patches/0001-mobile-tuning.patch`（26 行新增 / 1 行改动）。

## 重要更正（先说清楚）

我前面在配置模板里建议过 `dxvk.tilerMode = True` —— **这个建议是多余的**。
查源码后发现上游已自动识别 tiler 驱动并在 `src/dxvk/dxvk_device.cpp` 中自动启用：

```cpp
bool tilerMode = m_adapter->matchesDriver(VK_DRIVER_ID_MESA_TURNIP)
              || m_adapter->matchesDriver(VK_DRIVER_ID_QUALCOMM_PROPRIETARY)
              || m_adapter->matchesDriver(VK_DRIVER_ID_MESA_HONEYKRISP)
              || ... (ARM / PanVK / MoltenVK / Imagination / Broadcom / KosmicKrisp)
applyTristate(tilerMode, m_options.tilerMode);
hints.preferRenderPassOps = tilerMode;
hints.preferCachedMemory  = tilerMode;
```

Turnip 已在列表里，所以你的设备上它**本来就是开着的**。相关文档与配置模板已同步修正。

## 补丁一：移动端/瓦片 GPU 预留内存余量

**文件**：`src/dxvk/dxvk_memory.cpp`（`updateMemoryHeapBudgets`）

**动机**：移动设备没有独立显存，驱动上报的 heap budget 与整个系统共享物理内存，偏乐观。
本机实测：15.6 GB 总量但**可用仅 7.1 GB**，且依赖 8 GB swap。

**做法**：当适配器属于 tiler/移动驱动（Turnip / Qualcomm / Honeykrisp / ARM / Imagination），
且用户**未**显式设置 `dxvk.maxMemoryBudget` 时，从 device-local 预算里再扣掉 20% 作为余量。

**风险与退路**：可用纹理/缓冲上限降低 20%。若某游戏在本机因此报内存不足，
设置 `dxvk.maxMemoryBudget = 0` 是无效的（0 就是“未设置”），请改成任意大于 0 的值
（如 4096），补丁就不生效（显式值优先）。

## 补丁二：移动驱动下限制着色器编译 worker 数

**文件**：`src/dxvk/dxvk_pipemanager.cpp`

**动机**：上游的自动值是 `hardware_concurrency()`（本机=8），仅在 32 位平台才限到 8。
而移动 SoC 是 big.LITTLE，大核只有少数；着色器编译主要是**内存带宽受限**，
无脑铺满小核反而拉长总编译时间、加剧发热。

**做法**：在 Turnip / Qualcomm / Honeykrisp 上，当用户未显式指定时把 worker 数限到 4。

**风险与退路**：首次编译总量可能不降反升（但帧时间抖动更小）。
想恢复自由调度就设 `dxvk.numCompilerThreads = 8`（显式值优先）。

## 如何应用 / 如何构建

手动应用：
```bash
git clone --depth 1 -b v3.1.1 https://github.com/doitsujin/dxvk dxvk-src
cd dxvk-src && git submodule update --init --recursive
git apply /path/to/patches/0001-mobile-tuning.patch
./package-release.sh 3.1.1-mob . --no-package
```

用本仓库流水线（`patches` 参数可填多个 URL，逗号/空格分隔）：
```
source_repo = doitsujin/dxvk
ref         = v3.1.1
patches     = https://raw.githubusercontent.com/as14725836/d9vk/master/patches/0001-mobile-tuning.patch
version_name= 3.1.1-mob
release_tag = dxvk-3.1.1-mob
fix_mingw_headers = true
```

## 如何评估效果（很重要）

这两个补丁目前只保证**能编译、逻辑自洽**，设备上的实际效果需要你自己 A/B：

```bash
# A：官方版
DXVK_HUD=fps,frametimes ./scripts/wine-stable-launch.sh game.exe 1280x720 "$PREFIX"
# B：打了补丁的 dxvk-3.1.1-mob，同样的场景走一遍
```
对比**帧时间曲线**（不是平均帧）：卡顿尖峰变矮、或者长时间游玩不再被杀，才算真的有效。

## 后续可做的源码方向（未做，待评估）

- `d3d9.deviceLocalConstantBuffers` 的 `Auto` 分支目前“只在独显上开”，可考虑对 2D/galgame 负载放宽；
- 基于系统可用内存（`/proc/meminfo`）动态推导预算上限，而不是固定百分比；
- 这些都需要先有实测数据支撑，否则就是拍脑袋改默认值。

---

# 2026-10-31 修订：三个补丁的重新审查

上一篇文档只覆盖了 `0001`，并且当时没有 `0002` / `0003`。本次对三个补丁做了
完整的源码级复验（真实 mingw 交叉编译 + 逐文件 `-fsyntax-only`），结论与改动如下。

## 复验环境

```
DXVK      v3.1.1  (b1a1c99)
编译器     x86_64-w64-mingw32-g++ 13-posix
Vulkan    KhronosGroup/Vulkan-Headers (master，系统包版本过旧不满足 DXVK 3.1.1)
依赖      dxbc-spirv (dxbc / ir / sm3 / util)
```

结果：四个受影响文件全部 `PASS`（`dxvk_memory.cpp`、`dxvk_pipemanager.cpp`、
`dxvk_device.cpp`、`d3d9_constant_buffer.cpp`）。

## 修订一：`0002` 曾经重复实现 `tilerMode`

原 `0002` 在自己的局部定义了 `mobileTilerHints`（只列 3 个驱动）：
```cpp
const bool mobileTilerHints =
     m_adapter->matchesDriver(VK_DRIVER_ID_MESA_TURNIP)
  || m_adapter->matchesDriver(VK_DRIVER_ID_QUALCOMM_PROPRIETARY)
  || m_adapter->matchesDriver(VK_DRIVER_ID_MESA_HONEYKRISP);
```
但同一函数上方 20 行，上游**已有** `tilerMode`（列出 11 个 tiler 驱动）。
现改为直接复用 `tilerMode`，并额外要求 `isUnifiedMemoryArchitecture()`，
以免误伤“报了 tiler 驱动的独显”。

## 修订二：`0002` 不再默认打开 `preferComputeMipGen`

上游在这行正上方写着：
> Compute-based mip generation has some potential for performance
> regressions or driver issues. Just enable it on Nvidia and RADV
> (GFX10+) for now, where it is proven to work.

原补丁无视这条，直接给全部移动 tiler 打开。现改为**默认关闭**，
需要时用 `DXVK_TURNIP_COMPUTE_MIPGEN=1` 显式开启（便于 A/B 基准）。

`preferDescriptorByteOffsets` 仍然默认开（这一项没有对应的上游风险警告）。

## 修订三：`0003` 的判断标准与覆盖面

原补丁用 `vendorID` 判断，且只列了 3 个 vendor：
```cpp
if (vendorId == 0x5143u || vendorId == 0x13B5u || vendorId == 0x1010u)
```
三个问题：
1. 与 `0001` / `0002` 的 `matchesDriver()` 风格不一致；
2. **漏了 Honeykrisp**，而 `0001` / `0002` 都包含它；
3. 语义过宽 —— 任何高通/ARM/Imagination 设备都命中，包括很老的 Adreno 3xx/4xx，
   这些 GPU 上 device-local 常量缓冲未必更快。

现改为 `matchesDriver()` + `isUnifiedMemoryArchitecture()`，
并在列表里补齐 Honeykrisp / PanVK。

## 修订四：`0001` 增加了可调开关

原 `0001` 的 20% 硬编码且无法关闭（另两个补丁都有 `DXVK_TURNIP_EXPERIMENTS=0` 退路）。
现在可用环境变量调整：

```bash
# 预留 20%（默认值，不设即为此值）
# 预留 0%，完全关闭该行为
DXVK_MOBILE_MEMORY_HEADROOM_PCT=0
# 预留 10%
DXVK_MOBILE_MEMORY_HEADROOM_PCT=10
```
取值上限 50%，非法值（非数字 / 超范围 / 带尾随字符）会自动回退到默认 20%。

## 环境变量汇总

| 变量 | 默认 | 作用 |
|---|---|---|
| `DXVK_TURNIP_EXPERIMENTS` | 未设（=启用） | 设 `0` 关闭 `0002`/`0003` 的移动端默认行为 |
| `DXVK_MOBILE_MEMORY_HEADROOM_PCT` | `20` | `0001` 的内存预留百分比，`0` 关闭 |
| `DXVK_TURNIP_COMPUTE_MIPGEN` | 未设（=关闭） | 设 `1` 才启用 compute mipgen 实验项 |

## 仍然缺失的一环：实机数据

以上都是**代码层面的正确性**验证（能编译、逻辑自洽、不违背上游判断）。
真正缺的是 **Adreno 实机基准**：

- `preferDescriptorByteOffsets` 在 Turnip 上是否真的更快？
- `0003` 的 device-local 常量缓冲在各代 Adreno 上的收益/代价？
- `0001` 的 20% 预留是否过大（某些大纹理游戏可能反而更早 OOM）？

这三个问题没有实机数据无法回答。建议先在 A6xx / A7xx 各一台设备上做
“打好补丁 vs 不打补丁”的帧率对比，再决定是否把 `preferComputeMipGen` 之类
的实验项改为默认开。

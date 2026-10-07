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

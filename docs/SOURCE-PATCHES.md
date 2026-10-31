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
---

# 补丁四：Adreno 分代识别（`0004-adreno-generation.patch`）

针对 `v3.1.1`，新增 7 个文件改动（+361 / −1）。

## 动机：deviceID 无法可靠识别 Adreno 型号

Mesa 27 的 turnip 在 `src/freedreno/vulkan/tu_device.cc:1327` 这样上报：

```c
props->deviceID = pdevice->dev_id.chip_id;
```

但两侧宽度不一致：

| 侧 | 类型 | 宽度 |
|---|---|---|
| `fd_dev_id.chip_id`（freedreno） | `uint64_t` | 48 位有效 |
| `VkPhysicalDeviceProperties::deviceID` | `uint32_t` | 32 位 |

赋值时高 16 位被静默截断。对照 `freedreno_devices.py` 的实际 chip_id：

| 完整 chip_id | 截断后 deviceID | 设备名 |
|---|---|---|
| `0x00be06030500` | `0x06030500` | Adreno 8c Gen 3 |
| `0x007506030500` | `0x06030500` | Adreno 7c+ Gen 3 |
| `0x006006030500` | `0x06030500` | Adreno 7c+ Gen 3 Lite |
| `0xffff06030500` | `0x06030500` | Adreno 7c+ Gen 3 |

**四个不同的 GPU 上报同一个 deviceID。** 其中既有 Gen8（8c）也有 Gen7（7c+），
任何基于 deviceID 的分代逻辑都会把它们混为一谈。

同一个截断还影响其他地方，`tu_device.cc:116`：

```c
uint32_t chip_id = device->dev_id.chip_id;   // 用于 pipelineCacheUUID
```

这意味着不同型号可能共享 pipeline cache UUID 前缀。

## 方案：从 deviceName 解析

`deviceName` 由 turnip 通过 `fd_dev_name()` 填入，格式规整：

| 名称样例 | 来源 |
|---|---|
| `Adreno (TM) 830` | 标准 |
| `Turnip Adreno (TM) 830 (raytracing disabled)` | 带前缀/后缀 |
| `Adreno 623` | 无 (TM) |
| `Adreno 7c+ Gen 3` | c 系列 |
| `Adreno 8c Gen 3` | c 系列 |
| `Adreno X1-85` | X 系列 |
| `Adreno (TM) X2-90` | X 系列 |

新增 `src/dxvk/dxvk_adreno.{h,cpp}`，把这些名称解析成：

```cpp
enum class AdrenoGen : uint8_t { Unknown, Gen6, Gen7, Gen8 };

struct AdrenoInfo {
  AdrenoGen gen;          // 代际
  uint32_t  model;        // 型号数字（830 / 623 / 702；c/X 系列为 0 或系列号）
  bool      isCFamily;    // 7c+ / 8c
  bool      isPlusVariant;// 带 "+"
};
```

## 对外接口

`DxvkAdapter` 新增三个方法（`src/dxvk/dxvk_adapter.h`）：

```cpp
AdrenoInfo adrenoInfo() const;                        // 完整信息（惰性缓存）
AdrenoGen  adrenoGen()  const;                        // 只要代际
bool       isAdrenoAtLeast(AdrenoGen gen) const;      // 代际比较
```

实现用 `mutable` 成员做惰性缓存，避免每次调用都解析字符串。

## 用法示例：改进 D3D9 MSAA 判定

`src/d3d9/d3d9_adapter.cpp` 原本有一段逻辑：

```c
if (!(availableFlags & sampleFlags) && dst.Format != VK_FORMAT_UNDEFINED) {
  // Adreno 7XX GPUs cannot report general support for 8x MSAA ...
```

问题是当 `dst.Format == VK_FORMAT_UNDEFINED` 时直接跳过逐格式查询，
而在 Adreno 上这个早期返回会误判 8x MSAA 不支持。现在：

```c
const bool adrenoNeedsPerFormatMsaa =
    m_adapter->isAdrenoAtLeast(AdrenoGen::Gen7);

if (!(availableFlags & sampleFlags)
 && (dst.Format != VK_FORMAT_UNDEFINED || adrenoNeedsPerFormatMsaa)) {
```

Adreno Gen7+ 即使 `dst.Format` 未定义也走逐格式查询，其它厂商行为不变。

## 单元测试

`tests/adreno_test.cpp`，覆盖 24 个用例：

```bash
g++ -std=c++17 -I src/dxvk -o /tmp/adreno_test tests/adreno_test.cpp src/dxvk/dxvk_adreno.cpp
/tmp/adreno_test
```

覆盖范围：
- 全部 A6xx / A7xx / A8xx 数字型号（623 / 704 / 722 / 735 / 753 / 810 / 829 / 830 / 840）
- Turnip 前缀与后缀（`Turnip Adreno (...)`、`(raytracing disabled)`）
- c 系列（`7c+ Gen 3` / `7c+ Gen 3 Lite` / `8c Gen 3`）
- X 系列（`X1-85` / `X2-90`）
- 非 Adreno（llvmpipe / NVIDIA / AMD / Intel）必须返回 `Unknown`
- 空字符串与 `nullptr`
- **关键**：deviceID 碰撞的四个设备必须能被区分

实测结果：**24/24 PASS**。

## 解决的另一个问题

`dxvk_device.cpp` 现在会记录解析出的代际：

```
info:  Adreno generation: 8
```

排查用户问题时，日志里能直接看到 DXVK 认为这是哪一代 Adreno，
比让用户去猜 deviceID 对应什么型号可靠得多。

## 已知边界

1. **c 系列 model 为 0**。`7c+ Gen 3` 这类名称里没有可提取的三位数字，
   所以只能给出代际（Gen7）而给不出精确型号。要区分 `7c+` 和 `7c+ Lite`
   需要看 `isPlusVariant`，但 Lite 与普通版无法从名称区分 —— 这需要
   mesa 侧在 deviceName 里带上更精确的信息。

2. **X 系列映射是经验性的**。`X1` → Gen7、`X2` → Gen8 依据的是
   mesa 设备表里 X1-85/X1-45 位于 A7xx 区块、X2-85/X2-90 位于 A8xx 区块。
   若高通后续调整命名，需要同步更新 `dxvk_adreno.cpp`。

3. **依赖 turnip 的命名格式**。如果用户用 `drirc` 的
   `force_vk_devicename` 覆盖了设备名，解析会失效（返回 `Unknown`），
   此时所有 Adreno 特化逻辑自动退回上游行为 —— 这是有意的安全默认值。

## 建议的后续 mesa 侧改动（未包含在本补丁）

如果要彻底解决，mesa 侧应该：

1. `tu_device.cc:116` 改用 `uint64_t` 计算 pipelineCacheUUID，
   避免不同型号共享 UUID。
2. 考虑在 `VkPhysicalDeviceProperties` 之外，通过
   `VK_KHR_get_physical_device_properties2` 或自定义扩展暴露完整 48 位 chip_id。
   （MR !44985 的讨论范畴）

在 mesa 侧改之前，本补丁的 deviceName 解析是唯一可行的 DXVK 侧方案。
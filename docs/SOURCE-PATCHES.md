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
---

# 补丁五：移动端 GPU 身份与 D3D9 伪装（0005-mobile-gpu.patch）

针对 v3.1.1，改动 4 个文件（+6 / -1）。

## 问题：D3D9 与 DXGI 对 Adreno 的厂商处理不一致

DxvkGpuVendor 枚举只有 Amd / Nvidia / Intel，Qualcomm(0x5143)、ARM(0x13b5)
被归为非经典厂商，导致 D3D9 和 DXGI 行为不一致：

- D3D9 (d3d9_adapter.cpp)：isNonclassicalVendorId 为真，默认伪装成 AMD RX 6700 XT
- DXGI (dxgi_adapter.cpp)：无此逻辑，保留真实 vendor ID

同一个游戏，D3D9 报告 AMD，D3D11/12 报告 Adreno，可能触发初始化异常。

## 改动

1. dxvk_adapter.h：DxvkGpuVendor 增加 Qualcomm / Arm
2. d3d9_options.{h,cpp}：新增 d3d9.hideMobileGpu 配置项，默认 True
3. d3d9_adapter.cpp：hideGpu 改为 isNonclassicalVendorId && options.hideMobileGpu

## 用法

```ini
d3d9.hideMobileGpu = False   # 暴露真实 Adreno 身份
d3d9.hideMobileGpu = True    # 默认，伪装成 AMD
```

## 已知边界

只影响 D3D9；DXGI 本身不伪装移动端厂商。完全对齐需给 DXGI 也加开关，留待后续。

---

# 补丁六：DXGI 侧移动端 GPU 伪装开关（0006-mobile-gpu-dxgi.patch）

针对 v3.1.1，改动 3 个文件（+11 / -1）。

## 目的

补丁五给 D3D9 加了 d3d9.hideMobileGpu，但 DXGI（D3D10/11/12）侧
原本就不伪装移动端厂商，两侧默认行为不一致：

- D3D9 默认伪装（hideMobileGpu=True）
- DXGI 默认不伪装（无此选项）

本补丁给 DXGI 也加上 dxgi.hideMobileGpu，默认 False（保持 DXGI 现状），
让用户可以主动对齐两侧。

## 改动

1. dxgi_options.{h,cpp}：新增 dxgi.hideMobileGpu，默认 False
2. dxgi_adapter.cpp：hideGpu 逻辑增加 Qualcomm/Arm 分支

## 用法

```ini
dxgi.hideMobileGpu = True    # 让 DXGI 也伪装成 AMD，与 D3D9 对齐
dxgi.hideMobileGpu = False   # 默认，保留真实 Adreno 身份
```

## 对齐后的完整方案

现在 D3D9 和 DXGI 各自有独立的 hideMobileGpu 开关，用户可按需组合：

- 完全一致伪装：d3d9.hideMobileGpu=True + dxgi.hideMobileGpu=True
- 完全一致暴露：d3d9.hideMobileGpu=False + dxgi.hideMobileGpu=False

注意：两个开关默认值不同（D3D9 默认 True，DXGI 默认 False），
这是为了保持各自上游的默认行为不变。

---

# 补丁七：GPLAsync 异步管线编译（0007-gplasync.patch）

来源：https://gitlab.com/Ph42oN/dxvk-gplasync （dxvk-gplasync-3.1.1-1.patch）

针对 v3.1.1，改动 8 个文件。

## 作用

DXVK 默认在首次使用某个 pipeline 时同步编译着色器，这会在游戏里
造成明显的卡顿（stutter）。GPLAsync 补丁引入异步管线编译：

- 渲染目标（render target）连续被绘制若干帧后，判定为「稳定」，
  此时允许新 pipeline 在后台线程编译，主线程不等待。
- 编译期间该 pipeline 不绑定，等下一帧编译完成后再使用，从而
  消除同步编译造成的卡顿。

## 与上游的差异（适配说明）

上游 gplasync 补丁基于 DXVK 的 master 分支，其中
`status.store()` 调用带 `std::memory_order_release` 参数。
但 DXVK v3.1.1 里该调用是单参数的 `status.store(status)`。

本仓库的 0007 已针对 v3.1.1 做了适配：把上下文行中的
`status.store(status, std::memory_order_release)` 改为
`status.store(status)`，其余内容与上游完全一致。

## 新增配置项

```ini
# dxvk.conf
dxvk.enableAsync = True    # 默认，启用异步管线编译
dxvk.enableAsync = False   # 禁用（退回上游同步编译）

# 也可以用环境变量运行时关闭
DXVK_ASYNC=0
```

## 适用场景

对 Adreno/Turnip 移动端尤其有价值：移动端 GPU 的 shader 编译
相对较慢，同步编译造成的卡顿更明显。配合 0001 的编译线程数
调整（big.LITTLE 适配）效果更好。

## 注意

异步编译有一个已知权衡：pipeline 首次出现的那一帧可能短暂
使用占位/旧 pipeline（或跳过该 draw），视觉上可能有一帧的
轻微闪烁。这是所有 async 方案的固有代价，换取的是消除
长卡顿。

---

# 补丁八：Turnip 禁用 swapchain present fence（0008-turnip-swapchain-fence.patch）

针对 v3.1.1，改动 1 个文件（+9 / -1）。

## 症状

在 Turnip（含 XmoBox 等第三方魔改版）上，部分 D3D9 游戏在 Device reset
后卡黑屏。对照测试：

- DXVK 1.6.1 正常
- DXVK 2.4.1（及 gplasync 版）正常
- DXVK 2.5.3 官方黑屏
- DXVK 3.1.1（含 gplasync）黑屏

## 根因

DXVK 2.5.x 引入提交 a5dc340「Use swap chain fences to synchronize WSI
semaphores」，依赖 EXT_swapchain_maintenance1 的 present fence。

Turnip 报告支持 swapchainMaintenance1，但其 present fence 实现有缺陷：
fence 永不 signal。DXVK 的 waitForSwapchainFence() 以 ~0ull 超时无限等待，
导致 present 阻塞、黑屏。Device reset 后重建 swapchain 时尤其明显。

## 修复

在 turnip 驱动上强制 m_hasSwapchainMaintenance1 = false，回退到 2.4.1
的无 fence 路径（该路径已知在 Turnip 上正常）。

对齐上游已有的 Gamescope 先例：上游自己就用 ENABLE_GAMESCOPE_WSI 环境
变量绕过 Gamescope WSI 的同类 fence 不 signal 问题。

```cpp
if (m_device->adapter()->matchesDriver(VK_DRIVER_ID_MESA_TURNIP))
  m_hasSwapchainMaintenance1 = false;
```

## 影响

仅 Turnip 驱动受影响，回退到 pre-2.5.x 的 present 同步方式（与 2.4.1
一致，已被验证稳定）。桌面驱动（AMD/NVIDIA/Intel）行为不变。

## 备注

这个问题的根本是 Turnip 的 swapchainMaintenance1 实现缺陷。若未来
上游 Turnip 修复了 present fence，本补丁可以移除。

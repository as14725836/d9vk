# 向 Turnip (Mesa / Adreno) 定向优化：能做什么、已做什么

结论先说：**DXVK 上游已经对 Turnip 做了不少定向处理**，不是一句“通用代码”而已。
下面是逐行核对的结果与我们的增量。

## 一、上游已经为 Turnip 做的事（附文件行号，可核验）

### 1. Tiler 模式自动开启（`src/dxvk/dxvk_device.cpp:725`）
```cpp
bool tilerMode = m_adapter->matchesDriver(VK_DRIVER_ID_MESA_TURNIP)
              || ... Qualcomm / Honeykrisp / ARM / PanVK / MoltenVK / Imagination ...
applyTristate(tilerMode, m_options.tilerMode);
hints.preferRenderPassOps  = tilerMode;
hints.preferCachedMemory   = tilerMode;
```
Turnip 在列表里 → 你的设备上**本来就是开着的**（这修正了我早期的一个错误建议）。

### 2. 大型常量数组的 lowering 在 Mesa 上被**故意关闭**（`dxvk_device.cpp:823`）
```cpp
// Mesa drivers generally optimize large constant arrays to a buffer, some other
// drivers do not and suffer a significant performance loss. Enable lowering on
// those drivers.
if (!matchesDriver(MESA_RADV) && !NVK && !MESA_TURNIP && !HONEYKRISP && ...)
  m_shaderOptions.flags.set(DxvkShaderCompileFlag::LowerConstantArrays);
```
注意条件里的 `!MESA_TURNIP`：**正因为 Turnip 自己能做好，才把 lowering 关掉**。
这是典型的“驱动定向优化”，也提醒我们：不是所有开关“开了就快”。

### 3. 两个被明确排除在 Turnip 之外的能力（上游的理由是“未经验证”）
```cpp
// 744 行
// Compute-based mip generation has some potential for performance
// regressions or driver issues. Just enable it on Nvidia and RADV...
hints.preferComputeMipGen = (NVIDIA || (RADV && minSubgroupSize == 32));

// 751 行
// On AMD we can expect it to be optimal to simply pass the heap offset
// to descriptor memory through as-is to avoid some ALU.
hints.preferDescriptorByteOffsets = (RADV || AMD_OPEN_SOURCE || AMD_PROPRIETARY);
```
这两项就是“可能还能再压一点性能”的地方，但上游出于风险有意不开。

## 二、我们加的 Turnip 定向增量

### patch 0001（已发布在 dxvk-3.1.1-mob）
- 内存：Turnip/移动驱动下 device-local 预算再留 20% 余量
- 线程：Turnip/Qualcomm/Honeykrisp 下着色器编译 worker 限到 4

### patch 0002（本次）——**默认行为不变、需手动开启**的实验开关
```
DXVK_TURNIP_EXPERIMENTS=1
```
打开后在 Turnip 上额外启用：
1. `hints.preferComputeMipGen = true` —— mipmap 生成改走 compute 路径
   （代码位置：`dxvk_meta_mipgen.cpp:209` 分支）
2. `hints.preferDescriptorByteOffsets = true` —— 描述符直接传字节偏移
   （代码位置：`dxvk_pipelayout.cpp:363`）

**为什么做成开关而不是默认开启**：上游把这两项排除在外是有理由的（可能变慢或出错），
在没有你设备上的实测数据前，我不应该把未验证的改动塞进默认路径。

**怎么用**：
```bash
export DXVK_TURNIP_EXPERIMENTS=1
export DXVK_HUD=fps,frametimes      # 看帧时间，不要只看平均帧
./scripts/wine-stable-launch.sh game.exe 1280x720 "$PREFIX"
# 对比：unset DXVK_TURNIP_EXPERIMENTS 再跑一遍同一个场景
```

## 三、还没做、但值得做的 Turnip 定向方向

| 候选 | 依据 | 为何先不做 |
|---|---|---|
| `d3d9.deviceLocalConstantBuffers` 的 `Auto` 分支目前只在独显上开 | 官方 doc 写明 Auto = 仅独显 | 需要实测帧时间；unified memory 上收益不明确 |
| 基于系统可用内存动态推导预算（而非固定 20%） | 本机 7.1GB 可用 / 8GB swap | 需要读取 /proc，属平台相关代码，破坏可移植性 |
| Turnip 专属的 render pass 策略微调 | tilerMode 已有 `preferRenderPassOps` | 没有 profiler 数据支撑就是拍脑袋 |

**判断标准**：只有能在你设备上看出帧时间差异（或消除崩溃/画面错误）的改动，才值得进默认路径；
其余一律留在 `DXVK_TURNIP_EXPERIMENTS` 后面。

## 四、本次验证

- patch 0002 基于干净树生成，`git apply --check` 通过
- CI 编译（x64 + x32）作为类型/语法验证
- patch 0001 已在 `dxvk-3.1.1-mob` 上编译通过；另已随 master 快照（`dxvk-master-5b94142-mob`）
  验证了**在 v3.1.1 之后 63 个提交的新代码上仍能干净应用**

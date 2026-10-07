# 两个高频问题：DXVK 黑屏只能用 wined3d / OP 视频卡顿

## 一、为什么有些游戏用 DXVK 黑屏，换成 wined3d 就正常

先分清一个前提：**这不是“DXVK 有 bug”，而是两条实现的能力边界不同。**
按概率从高到低：

### A. DXVK 根本没被加载（最常见）
Wine 的 override `n,b` = 先试 native，**加载失败就用 builtin**。所以“DXVK 黑屏、wined3d 正常”
很多时候意味着 DXVK 的 DLL **压根没跑起来**：
- 位数不对：32 位游戏必须用 `x32/` 放 `syswow64`，放到 `system32` 就白搭
- CLI override 没生效（变量没 export、前缀不一致）
- 放错前缀（WINEPREFIX 指的是另一个）

**判定**：用 `DXVK_LOG_LEVEL=info` 启动，看游戏目录/工作目录下有没有生成 `d3d9.log` 或 `dxgi.log`。
**没有日志 = 根本没加载**，这时候去调 DXVK 的任何选项都是徒劳。

### B. 加载了，但设备创建失败（驱动能力不足）
DXVK 2.0+ 硬要求 Vulkan 1.3 及一批扩展；驱动被裁剪或版本旧就会在 `vkCreateDevice` 阶段失败。
**判定**：`d3d9.log` 里出现 vulkan 错误码 / `unsupported` / `feature not available`。
**对策**：用我们库里低一档的版本试试（`dxvk-2.7.1` / `dxvk-1.10.3`）——1.x 只要求 Vulkan 1.1。

### C. 能力位（caps）推导不同，老游戏选了坏路径
这是最容易被误认为“DXVK 坏了”的一类。DXVK 的 D3D9 caps 是**根据真实硬件推导**的，
而且会主动屏蔽它不打算支持的能力。我核对了源码，比如 `src/d3d9/d3d9_adapter.cpp` 里：

```c
/* | D3DCAPS3_DXVAHD */
/* | D3DCAPS3_DXVAHD_LIMITED */;
```

—— DXVAHD 相关位是被**注释掉**的（即不对外声明）。wined3d 则是另一套策略：
它对外报告的是“仿真层面”的 caps，并长期累积了针对特定游戏/驱动的兼容处理。
结果是：**同一个游戏在 DXVK 下会认为“某个能力没有”从而选择另一条渲染路径**，
如果那条路径恰好没被实现或实现不全，就是黑屏；而 wined3d 里它能走通。
这类情况**换 wined3d 就是正解**，不是配置问题。

### D. API 本身不在 DXVK 覆盖范围
- D3D7 及更老 / DirectDraw：走 `ddraw` → wined3d，DXVK 不参与
- D3D8：DXVK 从 2.7 系列才开始有 `d3d8`（更早版本没有）
- D3D10.1：DXVK 2.0+ 不再提供 `d3d10.dll`/`d3d10_1.dll`

### E. 特性是显式 stub
DXVK 有不少 `stub` / `semi-stub`（下面第二节就会看到一个）。依赖这些特性的游戏在 DXVK 下不出画面。

### 诊断流程（按顺序做，不要跳步）
1. `DXVK_LOG_LEVEL=info` 启动 → **有没有日志文件？**（决定 A 类还是 B–E 类）
2. 核对位数与 override；想排除回退干扰就写死 `d3d9=n`（此时失败会直接报错，容易定位）
3. 看日志里的 vulkan 错误 → B 类的话逐级降版本（3.1.1 → 2.7.1 → 1.10.3）
4. 都干净但仍黑屏 → 大概率是 C/D/E 类：**该游戏就该用 wined3d**

---

## 二、Galgame 的 OP 动画为什么卡，能不能“自动切到 OpenGL 去解码”

**不能，而且这个思路本身不成立。** 三条硬事实：

### 1) DXVK 里根本没有视频解码这条路径
我核对了 v3.1.1 源码，`src/d3d11/d3d11_video.cpp` 里是这样的：

```c
Logger::warn(str::format("D3D11VideoProcessorEnumerator::CheckVideoProcessorFormat: stub, format ", Format));
...
Logger::warn("D3D11VideoProcessorEnumerator::GetVideoProcessorCaps: semi-stub");
```

D3D11 视频处理是 **stub / semi-stub**；D3D9 侧连 DXVAHD 的 caps 都不声明（见上）。
也就是说：**DXVK 不提供任何 GPU 硬件解码能力**。

### 2) 视频解码在 Windows 架构里不属于 D3D
OP 视频走的是 DirectShow（Wine 的 `quartz`）/ Media Foundation（`mfplat`），
真正干活的是**独立的解码器 DLL**（wmv/ffdshow/LAV 那一类）。
在你这套环境里那些 DLL 是 **x86 代码，被 box64 逐指令翻译后再执行**。
所以瓶颈通常是：**用 CPU 翻译执行一个 x86 软件解码器**，而不是 GPU。

### 3) “切到 OpenGL 解码”在技术上没有这个机制
OpenGL 没有视频解码 API（只有纹理上传）；wined3d 也不会替你解码。
所以没有任何“自动切换”开关可以打开。

### 那么有效的办法是什么

**先确认瓶颈（不要猜）**：OP 开始播放时看 CPU 占用——如果某个核跑满，就是解码/翻译瓶颈，
后续优化才有的放矢。

按性价比排序：

| # | 做法 | 原理 | 注意 |
|---|---|---|---|
| 1 | **把 OP 视频转小**（降分辨率/降帧率/用简单编码） | 解码代价与像素数、帧数成正比 | 先备份原文件；容器/编码要尽量与原文件一致，否则游戏可能不认 |
| 2 | 让游戏**跳过 OP** | 多数引擎有设置项或按键 | 最彻底 |
| 3 | 换解码器 DLL（LAV 等） | 有时解码效率更好 | 在 box64 下往往**更慢**（更多 x86 指令），只能实验 |
| 4 | 用外部播放器 | 绕开游戏内置播放器 | 需引擎支持 |

工具：`scripts/galgame-op-transcode.sh`（基于 ffmpeg，**不覆盖原文件**，输出到 `out/` 目录）。

```bash
# 看看它打算干什么（默认只打印命令）
./scripts/galgame-op-transcode.sh movie/op.wmv
# 确认后真正执行
./scripts/galgame-op-transcode.sh movie/op.wmv --run
```

### 诚实边界
- 我没有在你的设备上逐帧实测过；上面关于“Wine 走 DirectShow/解码器独立”的描述是架构事实，
  但**具体某个游戏用哪个解析器、能不能吃下重新编码的文件**，需要你试（所以脚本默认不覆盖原文件）。
- 如果你的游戏用 Media Foundation 且 Wine 构建里带了 ffmpeg 后端，H.264 的解码可能比 MJPEG 更自然，
  但 CPU 代价更高。建议两种各转一份对比。

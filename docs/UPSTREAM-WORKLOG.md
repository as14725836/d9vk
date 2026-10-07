# 上游作者在实现什么（基于提交审查，可逐条核验）

**审查范围**：`doitsujin/dxvk` 从 `v3.1.1`（2026-09-15）到 master 的 HEAD（2026-10-05），
共 **63 个提交**、52 个文件（compare API）。改动热点：

| 目录 | 文件数 |
|---|---|
| `src/dxvk` | 21 |
| `src/d3d11` | 13 |
| `src/d3d9` | 6 |
| `src/util` | 4 |
| `src/d3d8` | 2 |

复现：`GET /repos/doitsujin/dxvk/compare/v3.1.1...master`

---

## 一、当前最大的工作流：Present timing（约 20 个提交）

这是一条成体系的提交链，不是零散修补：

```
54ebf7f2 [dxvk] Enable VK_EXT_present_timing if supported
eba1ad6c [dxvk] Enable VK_KHR_calibrated_timestamps as necessary
5913670e [dxvk] Add code for various present timing property queries
4bc70a81 [dxvk] Create swapchain with present timing enabled
36febd43 [dxvk] Request present timing if available
bf706d80 [dxvk] Add function to translate timestamps between different domains
56024247 [dxvk] Query present timings in present wait thread
76ecc487 [dxvk] Skip present wait for timed frames
eee6e5cb [dxvk] Sleep until target present time when absolute timing is used
04837ecf [dxvk] Do not engage CPU frame rate limiter if present timing is used
d731c5d5 [dxvk] Properly handle frame rate and present mode for present timing
396fa0f9 [dxvk] Adjust frame rate threshold for present timing
d495b308 [dxvk] Replace frame queue with fixed-size ring buffer
f63e290c [dxvk] Allow querying present time of the last frame
7df3596e [dxgi] Query frame statistics directly from the presenter
1e299d06 [dxvk] Add config to disable present timing features
e5ffd0fe [dxvk] Disable present timing by default   ← 注意这条
```

**在干什么**：用驱动的呈现时间能力（`VK_EXT_present_timing` + `VK_KHR_calibrated_timestamps`）
取代 DXVK 自带的 CPU 帧率限制器，做更精准的帧节奏与延迟控制。

**关键判断**：最后一条 `Disable present timing by default` —— 说明**该功能默认不开**，属于逐步推进中的新能力。
对我们的意义：Turnip 是否暴露 `VK_EXT_present_timing` 需要单独查；即便支持，默认也是关的。

## 二、D3D11 上传/staging 路径与互操作（13 个文件）

```
3200bb10 [d3d11] Fix infinite loop in AllocStagingBuffer
d6e0e947 [d3d11] Serialize staging buffer allocation requests in initializer
97a20610 [d3d11] Bump limits for staging memory in flight
850a013c [d3d11] Revise locking logic in device initializer
6fd968e9 [d3d11] Add config to ignore all calls to Flush()
984bc316 [d3d11] Fix submission synchronization with VR interop interfaces
47fe7563 [d3d11] Add interop interface for buffer resources
bf183854 [d3d11] Move function to lock buffer to public D3D11 interface
8104242c [dxvk] Add helper to return sharing mode info to app
```

**在干什么**：并发安全（无限循环、锁、串行化）+ 吞吐（放宽在飞 staging 上限）+ 新接口（VR/资源互操作）。
`ignore all calls to Flush()` 这个配置项很实用——专门治“游戏乱 Flush 拖性能”。

**对我们的意义**：z 这批改动与“司机在 box64 上多线程调度 + 慢速存储”的场景相关，值得跟。

## 三、d3d9 正确性维护（6 个文件） + d3d8 成熟化（2 个）

```
8d252af1 [d3d9] Preserve color inputs for D3DTOP_DOTPRODUCT3
68530156 [d3d9] Check the correct surface for multisampling in GetRTData
ec93112f [d3d9] Fix oversight with systemmem surfaces
e2c890ca [d3d9] Don't clear imported textures
a25e33e9 [d3d9] Improve GetRenderTargetData validation
271ad46d [d3d9] Clean up repeated 9Ex usage checks
b419e808 [d3d9] Initialize the device child device pointer
0abbe8a4 [d3d8] Encode float constant destination registers as D3DSPR_CONST
96dfda2e [d3d8] Use standard masks and shifts in encodeDestRegister
```

**对我们的意义**：d3d9 依然是活跃维护线（galgame/老游戏受益）；d3d8 还在补编码器细节。

## 四、着色器编译器子模块 `dxbc-spirv` 在持续改进

主仓里只能看到 `[meta] Update dxbc-spirv`（出现 3 次），真正的改动在子模块里：

```
c7f06970 ir: Add pass to extend PS outputs to vec4.
ed453716 sm3: Fix handling higher constant banks for SWVP shaders.
8dae2d85 ir: Properly check that getConstantAsSint is actually constant.
dcd27e1d ir: Remove back-edges to unreachable loop before removing loop header.
37a97745/304a7080 udiv lowering 重组
213d2b85 dxbc: Properly handle integer division by zero.
c5c1a5b9 sm3: Flush nan fog factor to 1.
```

**对我们的意义**：**盯 3.x 的更新不能只盯主仓**——着色器翻译的优化与修复发生在这里，
而它不跟主仓版本号走（印证了 `UPSTREAM-TREND.md` 里的判断）。

## 五、Reflex / 延迟与其余健壮性修复

```
5b94142f [dxvk] Handle TRIGGER_FLASH reflex marker
ac912ba4 [dxvk] Also allocate reflex frame ID on rendersubmit start
3dbf33cb [d3d11] Fix incorrect swapchain resize dimensions   ← 与“窗口尺寸/分辨率”同一区域
5cbf1083 [dxvk] Disable dual-source blending if fragment shader only has one export
c9a4b30b [dxvk] Fix funny mip gen edge cases when filtering from LDS
88aeeb31 [dxvk] Fix device fault address range reporting
076922bd [dxvk] Disable descriptor heap on AMD Proprietary
4bdfb9a1 [util] Enable more workarounds for Total War Pharaoh
```

`Fix incorrect swapchain resize dimensions` 跟之前那个 `185x2` 退化分辨率属于同一块代码区域，
值得留意后续版本是否连窗口尺寸协商一起修正。

---

## 六、结论：该怎么对待 master

| 判断 | 依据 |
|---|---|
| 主线当前重心是**正确性与健壮性**（同步、校验、边界），不是新的速度魔法 | 63 条里后者只有少量（staging 吞吐、present timing） |
| `present timing` 是正在推进的大特性，但**默认关闭** | `e5ffd0fe` |
| 子模块 `dxbc-spirv` 是 3.x 优化的真正所在地 | 两个仓库的提交分布 |
| **不建议把 master 当日用版本** | 3 周 63 个提交，属活跃开发线；默认值仍在调整 |
| **值得做**：出一个 master 快照包供测试，并验证我们的补丁在 master 上能否继续应用 | 本仓库已支持任意 ref 构建 |

下一步（已执行）：构建 `dxvk-master-<HEAD>` 快照，并同时测试 `patches/0001-mobile-tuning.patch`
在新代码上的可应用性（补丁若不能应用，CI 会在“叠加补丁”步骤直接报错，属预期内的检测）。

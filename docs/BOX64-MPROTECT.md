# 关于 `jiaxinchen-max/termux-app` 的 `box64-mprotect-patch-v1`：补丁到底在不在

## 一、先回答：**没有公开的补丁文件**

我把那个 Release 和它所在的仓库查了一遍，事实如下：

| 查询 | 结果 |
|---|---|
| Release 附件 | **只有 1 个二进制**：`box64-android-mprotect-patch-arm64`（25,587,264 字节，下载数 1）——**没有 .patch / .diff** |
| 该仓库是什么 | `termux/termux-app` 的 **fork**（Termux 应用本体），默认分支 `master-x11-submodule` |
| 在该仓库搜 `mprotect` 提交 | **0 条命中**（box64 源码根本不在这个仓库里） |
| 作者自述 | 发布说明写明 **"Not yet submitted upstream to ptitSeb/box64"** |

所以：**原始补丁没有公开**。能拿到的只有那个预编译二进制。

## 二、作者在发布说明里写的内容（原文要点）

- 基于 **box64 v0.4.5（upstream main @8f6ab59）** 的补丁构建；
- 改动是：**在 `my_mprotect()` 里，当 `box64_pagesize == X86_PAGE_SIZE` 时无条件去掉 `PROT_EXEC`**；
- 目的是绕过 Android `targetSdkVersion >= 29` 的 **W^X / SELinux 策略**（`untrusted_app` 拒绝在 app 私有存储支撑的内存上 `mprotect(PROT_EXEC)`）；
- 作者强调 **box64 从不原生执行 guest 页面**（它 JIT 到宿主 ARM64），所以宿主映射**本来也不需要真的可执行**；
- 与 `termux-pacman/glibc-packages` 的 issue #49 / PR #50（libc 的 mprotect 修法）同源；另有 `box64-wine-39bit-pitfalls` 一篇调查笔记。

## 三、我按上述描述**还原**了补丁（不是作者原件）

代码位置（box64 @ 8f6ab59，本地 grep 定位；GitHub 代码搜索索引不到这个函数）：

```
src/wrapped/wrappedlibc.c:4056   EXPORT int my_mprotect(x64emu_t* emu, void *addr, unsigned long len, int prot)
```

函数开头就是那个分支：

```c
if(box64_pagesize == X86_PAGE_SIZE) {
    int ret = mprotect(addr, len, prot);      // ← 这里在 Android 上会被 SELinux 拒绝
    ...
}
```

还原后的补丁：`patches/box64/android-wx-mprotect.patch`

```c
if(box64_pagesize == X86_PAGE_SIZE) {
    // [Android W^X workaround] ...
    prot &= ~PROT_EXEC;
    int ret = mprotect(addr, len, prot);
```

**验证**：已对该 commit 的源码树执行 `git apply --check` 通过，应用后 `1 file changed, 5 insertions(+)`。

**诚实边界（重要）**：
- 这份补丁是**我根据发布说明 + 源码位置重建的**，与作者实际改动**可能不完全一致**（例如他可能只剥离发给 `mprotect()` 的 host 参数，而保留 `updateProtection()/setGuestProtection()` 里的 guest prot 记账；我这里是按"无条件剥离"实现，两者对 guest 可见语义略有差别）。
- 作者做的是**无条件**剥离（不区分平台）。在宿主页大小同为 4096 的桌面上也会生效；如果你担心跨平台影响，可以把它包进 `#if defined(__ANDROID__)`。

## 四、两条可用路径

**路径 A：直接用作者的二进制（最省事，行为经过作者验证）**
```
https://github.com/jiaxinchen-max/termux-app/releases/download/box64-mprotect-patch-v1/box64-android-mprotect-patch-arm64
```

**路径 B：自己编译（用我这份还原补丁）**
```bash
git clone https://github.com/ptitSeb/box64
cd box64 && git checkout 8f6ab59
git apply /path/to/patches/box64/android-wx-mprotect.patch
cmake -B build -DARM64=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j"$(nproc)"
```

## 五、和咱们这套环境的关系

之前那条主线用的是 box64 **v0.3.9**；这条补丁针对的是 **0.4.5**。
如果你的目标是把环境升级到 0.4.x，这个 W^X 修复是**必需项**（否则在 targetSdk 较新的 Termux 上会因 `mprotect(PROT_EXEC)` 被拒而无法启动 JIT）。
要不要引入，建议先明确：升级到 0.4.x 会带来行为差异，最好单开一条环境来验证，不要直接覆盖现有可用的 0.3.9 环境。

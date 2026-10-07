# 上游源码审查：dxvk 在往哪些方向改进，我们怎么跟上

审查方法：用 GitHub API 逐版本对比 `src/` 目录、`.gitmodules`、`src/d3d10/meson.build`，
不看二手报道，只看仓库里实际存在的东西。

## 一、实测数据（可复现）

| 版本 | `src/` 子目录 | 子模块（.gitmodules） | d3d10.dll / d3d10_1.dll |
|---|---|---|---|
| v1.10.3 | d3d10 d3d11 d3d9 dxbc dxgi dxso dxvk spirv util vulkan | 无 | **有**（meson 里 d3d10_res / d3d10_1_res / d3d10_core_res 三个 shared_library） |
| v2.0 | 上面 + `wsi` | mingw-directx-headers、Vulkan-Headers、SPIRV-Headers | 只剩 d3d10core |
| v2.7.1 | 上面 + **`d3d8`** | 上面 + `subprojects/libdisplay-info` | 只剩 d3d10core |
| v3.1.1 | **移除 dxbc、dxso** | 上面 + **`subprojects/dxbc-spirv`** | 只剩 d3d10core |

复现命令：
```bash
for T in v1.10.3 v2.0 v2.7.1 v3.1.1; do
  echo "== $T"
  curl -s "https://api.github.com/repos/doitsujin/dxvk/contents/src?ref=$T" \
    | python3 -c "import json,sys;print(' '.join(sorted(x['name'] for x in json.load(sys.stdin) if x['type']=='dir')))"
  curl -s "https://raw.githubusercontent.com/doitsujin/dxvk/$T/.gitmodules" | grep path
done
```

## 二、方向解读（每条都有上面的证据支撑）

1. **门槛上移 + 依赖外置**：2.0 起硬要求 Vulkan 1.3，同时把 DX 头文件、Vulkan 头文件、SPIRV 头文件全部改成 git 子模块。
   → 对我们是好事也是坑：好事是不再依赖发行版的头文件版本（就是当初 d9vk 在 mingw-w64 ≥ 9 上 `D3D11_FORMAT_SUPPORT2` 重复定义那类问题的根因）；
   坑是**构建必须拉子模块**（`--recurse-submodules`），否则直接编译失败。我们的流水线已经是递归拉子模块。
2. **D3D8 回归**：2.7.1 起 `src/d3d8` 存在，D3D8 游戏从 2.x 中期开始能用了（不必再找 dxvk-sao）。
3. **显示/刷新率枚举化**：2.7.1 引入 `libdisplay-info` 子模块，对应 `d3d9.enumerateByDisplays`、
   `d3d9.forceRefreshRate` / `dxgi.forceRefreshRate` 这类开关——也就是用户遇到 `Buffer size: 185x2` 时相关的那条代码路径。
   → 结论仍然是：容器里固定虚拟桌面尺寸最稳，`enumerateByDisplays = False` 作为辅助。
4. **着色器前端模块化**：3.1.1 把 DXBC/DXSO 编译器抽成独立子模块 `dxbc-spirv`（`src/dxbc`、`src/dxso` 消失），
   并新增 `src/wsi`。这意味着今后 3.x 的着色器翻译优化会发生在子模块里，与主仓版本号解耦。
   → 盯更新要同时盯 `doitsujin/dxbc-spirv` 的提交，不能只看 dxvk 的 release。
5. **安装方式改变**：3.x 删除了 `setup_dxvk.sh`；2.0+ 不再提供 `d3d10.dll` / `d3d10_1.dll`。
   → 用户手册里“`setup_dxvk.sh install`”那套在新版本上直接不能用。

## 三、据此做的查缺补漏

| 缺口 | 处理 |
|---|---|
| 3.x 没有安装脚本 | 补 `scripts/setup_dxvk.sh`：通用（1.x/2.x/3.x/vkd3d-proton 都能用），自动按位数装到 system32/syswow64，自动备份 `.dxvk-bak`，`--uninstall` 一键回滚。已实测：12 个 DLL 安装、旧文件备份、回滚均正常 |
| 需要 D3D10.1 的游戏在 2.0+ 直接断 | 保留 `dxvk-1.10.3`（含 d3d10.dll / d3d10_1.dll），并在 README 标明 |
| 3.x 没有公开可用的 async 补丁 | 保留 `dxvk-async-2.0` 与 `dxvk-sao-1.11.1` 作为异步可选路径；不编造补丁 |
| 上游发新版后没人跟进 | `auto-update.yml` 每日自动探测 + 构建 + 发布（本次修了它的 GITHUB_OUTPUT 污染 bug 与 dxvk-sao tag 规范化） |
| 版本覆盖不密，回落定位粒度粗 | 阶梯补齐 2.1 / 2.2 / 2.4 / 2.5 / 2.6 / 2.7 / 3.0，并补 `dxvk-2.0` 纯主线 |
| 想要更快的默认构建 | 新增 `extra_flags` 输入，已用 `-O3 -flto` 出一个 `dxvk-3.1.1-opt` 做对照 |

## 四、还没解决的问题（诚实列出）

- **3.x 的异步/GPU 直提**：上游没有公开补丁，我们不做逆向工程式修改。
- **画面偏黄**：属于色彩空间/输出路径问题（`VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` 相关），
  现实做法是驱动层（Turnip）与容器输出配置对齐，DLL 换版本解决不了，见 `COMPATIBILITY.md`。
- `185x2` 这类退化交换链尺寸：DXVK 只是照窗口尺寸创建，根子在窗口/显示协商，已给固定虚拟桌面方案。

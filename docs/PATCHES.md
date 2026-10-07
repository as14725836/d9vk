# 可用补丁 / 衍生源码清单（截至 2026-10）

> 目的：为 Android + box64/Wine 环境筛选“能复现”（有源码或可应用补丁）的 DXVK 优化方案。
> 本仓库的 `build-dxvk` 流水线可以直接构建下表任一项，并使用 `patches` 参数叠加补丁 URL。

## 一、可复现（推荐）

| 方案 | 来源 | 支持版本 | 性质 | 我们的构建方式 |
|---|---|---|---|---|
| 主线 dxvk | `doitsujin/dxvk` | v0.90 - v3.1.1+ | 官方，含 D3D8/9/10/11 | `source_repo=doitsujin/dxvk&ref=vX.Y.Z` |
| async 补丁 | `Sporif/dxvk-async` 的 `dxvk-async.patch` | dxvk 1.4.3 - 2.0 | 异步编译 pipeline，降卡顿 | `ref=v2.0&patches=<patch raw url>` |
| dxvk-sao | `Digger1955/dxvk-sao` | 基于 dxvk 1.11 | Vulkan 1.1 + Async + D3D8 | `source_repo=Digger1955/dxvk-sao&ref=SAO-master-1.11.1` |
| 新工具链适配 | 本仓库 `scripts/fix-mingw-headers.py` | dxvk 1.7 - 1.11 | 仅在 GCC13/mingw13 上編译必需 | 流水线默认开启 `fix_mingw_headers` |

## 二、只能拿成品、无法复现（缺少源码/已下架）

| 方案 | 现状 | 说明 |
|---|---|---|
| gplasync（Ph42oN） | 原仓已下架，只剩镜像的构建脚本（`Waim908/dxvk-gplasync-mirror` 里只有 `ALL_VERSION.sh` 列了 v2.1-v2.6.2 的成品包名） | 基于 `VK_EXT_graphics_pipeline_library` 的异步方案；主线 2.x 可用，但补丁本体拿不到 |
| STAR ENGINE（`isygold/Star-Engine-DXVK-Releases`） | 仅发 zip（v2.7.1 带 ASYNC），无源码 | Android/Adreno 向调优，宣称消除卡顿；源码仓 `isygold/source-code-patch` 是空的 |
| VEGAS（`isygold/vegas-releases`） | 仅成品 | 其 dxvk.conf 含 `dxvk.vegas.*` 私有选项，主线不认 |
| dxvk-sarek（`Selam985/DXVK-Sarek-O3-LTO-Build` 等） | 只见构建产物/构建器 | 有 `WinterSnowfall/wroshyr_builder` 可构建，属另一条线 |

## 三、结论

1. **要在主线 3.x 上做“异步”，目前没有公开可用的补丁**（async 停在 2.0，gplasync 补丁不可得）。
   要异步就只能停在 `dxvk-2.0`（async）或 `dxvk-sao-1.11.1`（Vulkan1.1 + async）。
2. 其余“优化”多见于闭源成品（STAR ENGINE / VEGAS），不能合并进我们自己的构建。
3. 因此本仓库的策略是：**主线全版本阶梯 + 可复现补丁**，而不是转载闭源成品。

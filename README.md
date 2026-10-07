# dxvk / vkd3d-proton 预编译包（Android + box64/Wine）

本仓库提供面向 **Android + box64/Wine（Winlator 类环境）** 的 D3D8–D3D12 翻译层预编译包，
全部由 GitHub Actions 在本仓库内构建（可复现，不转载闭源成品）。

## 一、下载（Releases）

| Tag | 说明 | 适用 |
|---|---|---|
| `dxvk-3.1.1` | 主线最新（d3d8/9/10/11） | 驱动 Vulkan 1.3 → **首选** |
| `dxvk-3.0.2` `dxvk-2.7.1` `dxvk-2.6.2` `dxvk-2.5.3` `dxvk-2.4.1` `dxvk-2.3.1` `dxvk-2.0` | 主线阶梯 | 逐版本回落定位 |
| `dxvk-async-2.0` | 主线 2.0 + async 补丁 | 卡顿明显时 |
| `dxvk-1.10.3` / `dxvk-1.9.4` | 1.x（含 `d3d10.dll`/`d3d10_1.dll`） | 驱动只有 Vulkan 1.1、D3D10.1 游戏 |
| `dxvk-sao-1.11.1` | dxvk-sao（Vulkan 1.1 + Async + D3D8） | 老驱动 + 要 async |
| `vkd3d-proton-3.0.1` | **D3D12**（d3d12.dll / d3d12core.dll） | D3D12 游戏 |
| `v1.4.6` | d9vk 原版（仅 D3D9） | 历史对照 |

## 二、装完必须做的一件事

按位数放对位置 + 覆盖 native：
```bash
# 64 位 DLL → 前缀的 drive_c/windows/system32
# 32 位 DLL → 前缀的 drive_c/windows/syswow64
export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core=n,b"
```

## 三、遇到问题先看文档

- **黑屏 / 偏色 / 分辨率异常（如 `Buffer size: 185x2`）/ `D3D10CORE.DLL.D3D10CoreCreateDevice@20, aborting`**
  → [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)
- **驱动侧（Turnip/Mesa）能力与建议** → [`docs/MESA-TURNIP-AUDIT.md`](docs/MESA-TURNIP-AUDIT.md)
- **可用补丁/衍生版清单（哪些能复现、哪些只有成品）** → [`docs/PATCHES.md`](docs/PATCHES.md)
- **本仓库自己的源码级补丁（含对 tilerMode 的重要更正）** → [`docs/SOURCE-PATCHES.md`](docs/SOURCE-PATCHES.md) + [`patches/`](patches/)
- **配置模板** → [`dxvk.conf.android.example`](dxvk.conf.android.example)
- **Galgame / 2D 游戏专项** → [`docs/GALGAME.md`](docs/GALGAME.md) + [`dxvk.conf.galgame.example`](dxvk.conf.galgame.example)
- **性能调优总表** → [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)
- **上游正在实现什么（提交审查）** → [`docs/UPSTREAM-WORKLOG.md`](docs/UPSTREAM-WORKLOG.md)
- **向 Turnip 驱动定向优化** → [`docs/TURNIP-TUNING.md`](docs/TURNIP-TUNING.md)
- **线程与内存稳定性** → [`docs/STABILITY.md`](docs/STABILITY.md) + [`wine-stability.env`](wine-stability.env)
- **一条命令启动（性能环境变量 + 固定虚拟桌面尺寸）** → [`scripts/wine-perf-launch.sh`](scripts/wine-perf-launch.sh)

## 四、自己构建

| 流水线 | 用途 |
|---|---|
| `build-dxvk.yml` | 任意仓库/分支 + 可选补丁（`patches`）+ 可选优化选项（`extra_flags`，如 `-O3 -flto`）；可自动发布 |
| `build-vkd3d.yml` | vkd3d-proton（D3D12） |
| `auto-update.yml` | 每日检查上游 dxvk / dxvk-sao 新版本，自动构建并发布 |
| `build.yml` | 本仓库自身（d9vk）的构建 |

## 五、已知边界

- dxvk **不负责** D3D12（那是 vkd3d-proton）；也不提供 OpenGL。
- dxvk 2.0+ 起不再自带 `d3d10.dll`/`d3d10_1.dll`；3.x 起不再提供 `setup_dxvk.sh`。
- 主线 3.x 目前没有公开可用的 async/gplasync 补丁：要异步只能停在 `dxvk-2.0` 或 `dxvk-sao-1.11.1`。
- 本仓库不打包闭源成品（STAR ENGINE / VEGAS / gplasync 预编译包）。

## 六、致谢

[doitsujin/dxvk](https://github.com/doitsujin/dxvk)、[HansKristian-Work/vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton)、
[Sporif/dxvk-async](https://github.com/Sporif/dxvk-async)、[Digger1955/dxvk-sao](https://github.com/Digger1955/dxvk-sao)、
misyltoad/d9vk，以及所有上游贡献者。各项目遵循其原始许可（dxvk: zlib）。

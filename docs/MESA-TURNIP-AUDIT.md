# Mesa / Turnip 侧审查（针对 DXVK 运行需求）

审查对象：Mesa 主分支 `src/freedreno/vulkan/tu_device.cc`（Turnip 是 Android/Adreno 上跑 DXVK 的关键驱动）。

## 一、Vulkan 版本

```c
props->apiVersion =
   ((pdevice->info->chip >= 7) ? TU_API_VERSION :
      VK_MAKE_VERSION(1, 3, VK_HEADER_VERSION));
```

- A7xx 及以上（如运行本仓库环境的骁龙 8 Gen 2 / Adreno 740）：取 `TU_API_VERSION`，即**达到 Vulkan 1.4**。
- A6xx：也上报 **1.3**。

⇒ **主线 dxvk 2.x / 3.x 的硬性门槛（Vulkan 1.3）在 Turnip 上是满足的**，前提是你用的 Turnip 够新。

## 二、dxvk 2.0+ 依赖的能力（在 Turnip 中的情况）

| 能力 | Turnip | 证据 |
|---|---|---|
| dynamic rendering | 有 | `dynamic_rendering` 相关代码 11 处；`dynamicRenderingLocalRead*` 已置 true |
| `VK_EXT_extended_dynamic_state` / `_state2` | 有 | tu_device.cc 4 处 / 1 处 |
| `VK_EXT_graphics_pipeline_library` | 有 | 2 处（这是 gplasync 类补丁的前提） |
| `VK_KHR_robustness2` / `VK_EXT_robustness2` | 有 | 281 行、387 行；`nullDescriptor` 已支持 |
| `VK_KHR_synchronization2` | 有 | 307 行 |
| `VK_EXT_custom_border_color` | 有 | 2 处（D3D9 采样边界行为有用） |

## 三、结论与建议

1. **不要自己从零构建 Mesa/Turnip**：Android 上 Turnip 需要 NDK + Mesa 的 Android 构建链，且已有成熟构建器：
   - `v3kt0r-87/Mesa-Turnip-Builder`（★211，为 Magisk/EMOD 构建 Turnip 模块）
   - `ilhan-athn7/freedreno_turnip-CI`（★164）
   直接用它们出最新 Turnip，比我们审读 + 打补丁划算得多。
2. 要跑 `dxvk-2.x / 3.x`，设备上必须是**较新的 Turnip**（旧版上报 Vulkan1.1/1.2，会直接导致 DXVK 启动失败）。
3. 若只能用旧驱动，则停在 `dxvk-1.10.3`（Vulkan 1.1）或 `dxvk-sao-1.11.1`（Vulkan 1.1 + async）。
4. 对 D3D9 游戏（如 Heptagram.exe）最有价值的驱动侧特性：dynamic rendering、extended dynamic state、custom border color；
   若出现闪烁/黑屏，优先怀疑驱动版本而非 DXVK。

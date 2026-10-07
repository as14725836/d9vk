# 线程与内存：让 Wine + box64 + DXVK 跑得更稳

## 0. 本机实测数据（先看清楚约束）

| 项 | 实测值 | 含义 |
|---|---|---|
| MemTotal | 15,636,824 kB（≈15.6 GB） | 16 GB 机型 |
| **MemAvailable** | **7,121,036 kB（≈7.1 GB）** | 已用掉约 8.4 GB —— **可用内存偏紧** |
| SwapTotal | 8,388,604 kB（8 GB） | 已有压缩/交换内存，系统在依靠它 |
| CPU | 8 核 | big.LITTLE，翻译层/编译线程不能无限开 |

结论：策略应是**节流（限制线程与内存）**，而不是放开并发。

## 1. 线程层

### 1.1 同步原语（对多线程游戏影响最大）

**已核实的事实**：esync / fsync **不是 Wine 上游的东西** —— 上游 `wine-9.4` 的
`dlls/ntdll/unix/sync.c` 里搜不到 `fsync`，GitHub 代码搜索 `WINEESYNC repo:wine-mirror/wine` 也是 0 命中。
它们是 Proton / Wine-Staging 的补丁，而 TKG 系构建（你用的 `wine-9.4-dxgi-tkg-stg`）通常带 Staging。

**先验证再开**：
```bash
strings $(command -v wine) | grep -iE 'WINEESYNC|WINEFSYNC'
```
- 有输出 → 可以开 `WINEESYNC=1`（两者不要同时开，fsync 通常更快）
- 无输出 → 开了也只是没效果，不会更坏

### 1.2 线程数：限制优于放开

| 位置 | 变量 | 建议 |
|---|---|---|
| box64 | `BOX64_MAXCPU` | 8（或 6；减少调度抖动） |
| box64 | `BOX64_DYNAREC_BIGBLOCK` | **内存紧 → 1**；内存充裕 → 3 |
| DXVK | `dxvk.numCompilerThreads`（dxvk.conf） | 4（默认 0=自动，8 核上自动值偏大） |
| Wine | 不必要的后台服务（`wineboot` 后残留进程） | 用完即退，别留着 |

big.LITTLE 上真正的风险不是“核不够”，而是**线程被调度到小核后长时间空等**，
表现为偶发卡顿；限制总数比让它铺满 8 核更稳。

## 2. 内存层（收益排序）

1. **`MALLOC_ARENA_MAX=2`** —— glibc 默认每个线程可建独立 arena，Wine 进程线程多时
   虚拟内存会成倍膨胀；限为 2 是最经典的稳定化手段，代价近乎为零。
2. **限制 DXVK 的显存承诺**：
   - `dxvk.maxMemoryBudget = 1024~2048`（MB，0=自动）
   - `dxgi.maxDeviceMemory = 0`（别往大了写，否则驱动会超额承诺）
   - `d3d9.textureMemory = 100`（d3d9 纹理内存上限百分数）
3. **`BOX64_DYNAREC_BIGBLOCK=1`**（内存紧时）——翻译出的代码更少更小。
4. **`BOX64_MALLOC_HACK=0`** —— 0=最稳；1/2/3 更激进但可能崩。
5. **内核参数（需 root）**：`vm.max_map_count` 建议 ≥ 262144。
   Wine + box64 会做大量 mmap，Android 默认值偏低时表现为
   “突然 Cannot allocate memory”——用 `scripts/android-mem-tune.sh` 查看/写入。
6. **不要额外加大 swap**：你这台已有 8 GB swap，继续加只会把内存压力变成 I/O 压力，更卡。
   要做的反而是**不要在游戏前积压后台应用**，把那 7.1 GB 尽量留出来。

## 3. 崩溃了怎么判断是不是内存问题

```bash
# 内核有没有杀进程（OOM killer）
dmesg | grep -i -E 'oom|killed process'        # 需要 root；或用 logcat
dumpsys meminfo | head -30                    # Android 侧内存快照
# 进程峰值
VIRT=$(grep VmPeak /proc/<pid>/status)        # 观察 VmPeak / VmRSS
df -h ~/.cache                                 # 状态缓存放得下吗
```

常见特征：
- **OOM 被杀**：进程直接消失、无异常栈 → 查 OOM killer 日志
- **地址空间耗尽**：报 `Cannot allocate memory` 但有物理内存 → 查 `vm.max_map_count`
- **虚拟内存膨胀但 RSS 不高**：典型 glibc arena 过多 → 设 `MALLOC_ARENA_MAX=2`

崩溃栈则用 `WINEDEBUG=+seh`（平时别开）。

## 4. 一键使用

```bash
. ./wine-stability.env                                  # 稳定性环境预设
./scripts/wine-stable-launch.sh game.exe 1280x720 "$PREFIX"
```

- `wine-stability.env`：每个变量都标了来源与风险
- `scripts/wine-stable-launch.sh`：稳定性优先启动（不含任何激进提速）
- `scripts/android-mem-tune.sh`：默认只**打印**内核参数；加 `--apply` 才写入（需 root）

## 5. 诚实说明

- 本次我读到了设备内存数据（来自共享内核的 `/proc/meminfo`），但 `/proc/sys` 在当前
  环境不可读，**Shizuku 也没在运行**，所以内核参数我没动手改，只给了脚本。
- 上面所有 DXVK 键名与默认值均核对自上游 `dxvk.conf`；box64 变量名均见于官方 `box64.box64rc`。
- 稳定性调优建议一次只改一项，并记录“改了什么 / 现象变化”，否则无法归因。

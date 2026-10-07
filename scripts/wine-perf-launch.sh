#!/usr/bin/env bash
# wine-perf-launch.sh — 一条命令带齐性能环境变量 + 固定虚拟桌面启动游戏
#
# 用法：
#   ./wine-perf-launch.sh <game.exe> [分辨率] [WINEPREFIX]
#   ./wine-perf-launch.sh Heptagram.exe 1280x720
#
# 可调环境变量（都有默认值）：
#   DXVK_CACHE_DIR   着色器状态缓存目录（默认 ~/.cache/dxvk）
#   DXVK_HUD_VALUE   设为 fps,frametimes 之类可看帧率
#   BOX64_PERF       设为 0 可关闭下面的 box64 调优
set -u

GAME="${1:-}"
RES="${2:-1280x720}"
PREFIX="${3:-${WINEPREFIX:-}}"
[ -n "$GAME" ] || { echo "用法: $0 <game.exe> [分辨率] [WINEPREFIX]" >&2; exit 1; }
[ -n "$PREFIX" ] || { echo "未指定 WINEPREFIX" >&2; exit 1; }

export WINEPREFIX="$PREFIX"

# ---- 状态缓存：跨运行复用已编译着色器（收益最大的一步）----
CACHE="${DXVK_CACHE_DIR:-$HOME/.cache/dxvk}"
mkdir -p "$CACHE"
export DXVK_STATE_CACHE_PATH="$CACHE"

# ---- 日志与配置 ----
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"   # 关日志能省一点 CPU
export WINEDEBUG="${WINEDEBUG:--all}"
export DXVK_CONFIG_FILE="${DXVK_CONFIG_FILE:-$(dirname "$0")/../dxvk.conf.android.example}"
[ -f "$DXVK_CONFIG_FILE" ] || unset DXVK_CONFIG_FILE

# ---- 让 DXVK 的 DLL 优先于 Wine 内置 ----
export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core=n,b"

# ---- box64 调优（v0.3.9 官方 box64rc 里真实存在的变量）----
# 这些会在“性能”与“兼容性/精度”之间取舍：游戏出怪问题就把 BOX64_PERF 设 0
if [ "${BOX64_PERF:-1}" != "0" ]; then
  export BOX64_DYNAREC_BIGBLOCK=3        # 默认 2：更大基本块，更快，但更吃内存/编译时间
  export BOX64_DYNAREC_STRONGMEM=1       # 默认 1：内存序保真度下降可提速，取值越高越快但有风险
  export BOX64_DYNAREC_SAFEFLAGS=1       # 默认 2：置 1 提速，个别程序会崩
  export BOX64_DYNAREC_FASTNAN=1         # 默认 1：NaN 处理提速
  export BOX64_DYNAREC_FASTROUND=1       # 默认 1：舍入处理提速
  export BOX64_DYNAREC_CALLRET=1         # 默认 0：调用/返回优化
  export BOX64_DYNAREC_BLEEDING_EDGE=1   # 默认 1：为未识别指令假定最新扩展
  export BOX64_DYNAREC_FORWARD=128       # 默认 128：前向跳转块大小
  export BOX64_DYNACACHE=1               # 默认 0：把翻译结果缓存到磁盘，二次启动明显更快
  export BOX64_MAXCPU=8                  # 上限 CPU 线程数，防止调度抖动
fi

# ---- 固定虚拟桌面（避免 185x2 之类退化分辨率）----
export DXVK_HUD="${DXVK_HUD_VALUE:-}"
[ -n "$DXVK_HUD" ] || unset DXVK_HUD

echo "[*] 缓存目录: $CACHE"
echo "[*] 分辨率: $RES"
echo "[*] 启动: $GAME"
exec wine explorer /desktop=dxvk,"$RES" "$GAME"

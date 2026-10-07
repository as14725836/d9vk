#!/usr/bin/env bash
# wine-stable-launch.sh — 以“稳定性优先”的方式启动游戏
#
# 与 wine-perf-launch.sh 的区别：不做任何激进提速，只做
#   1) 多线程同步走 esync（若构建支持）
#   2) 限制 glibc arena，避免虚拟内存膨胀
#   3) 限制线程数与翻译代码内存
#   4) 关闭日志
#
# 用法： ./wine-stable-launch.sh <game.exe> [分辨率] [WINEPREFIX]
set -u

GAME="${1:-}"; RES="${2:-1280x720}"; PREFIX="${3:-${WINEPREFIX:-}}"
[ -n "$GAME" ] || { echo "用法: $0 <game.exe> [分辨率] [WINEPREFIX]" >&2; exit 1; }
[ -n "$PREFIX" ] || { echo "未指定 WINEPREFIX" >&2; exit 1; }
export WINEPREFIX="$PREFIX"

HERE=$(cd "$(dirname "$0")" && pwd)
[ -f "$HERE/../wine-stability.env" ] && . "$HERE/../wine-stability.env"

# 内存：限制 glibc 线程 arena（Wine 线程多，这一项收益最大）
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

# 线程：限制翻译层线程数（8 核 big.LITTLE）
export BOX64_MAXCPU="${BOX64_MAXCPU:-8}"
# 内存紧张时不要用大基本块（内存充裕可改 3）
export BOX64_DYNAREC_BIGBLOCK="${BOX64_DYNAREC_BIGBLOCK:-1}"

# 日志
export WINEDEBUG="${WINEDEBUG:--all}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"
export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core=n,b"

# 着色器缓存目录可写（避免每次重新编译导致的长时间卡顿）
CACHE="${DXVK_CACHE_DIR:-$HOME/.cache/dxvk}"
mkdir -p "$CACHE"; export DXVK_STATE_CACHE_PATH="$CACHE"

# 打印关键设置，方便出现问题时对照
echo "[*] WINEDEBUG=$WINEDEBUG  DXVK_LOG_LEVEL=$DXVK_LOG_LEVEL"
echo "[*] MALLOC_ARENA_MAX=$MALLOC_ARENA_MAX  BOX64_MAXCPU=$BOX64_MAXCPU  BIGBLOCK=$BOX64_DYNAREC_BIGBLOCK"
echo "[*] 同步: ${WINEESYNC:+esync 已开}${WINEFSYNC:+fsync 已开}"
echo "[*] 分辨率: $RES  →  $GAME"
exec wine explorer /desktop=dxvk,"$RES" "$GAME"

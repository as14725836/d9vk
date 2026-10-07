#!/usr/bin/env bash
# 在 Wine + box64 环境下以“固定尺寸虚拟桌面”启动游戏，规避：
#   - 交换链尺寸退化（日志里 Buffer size: 185x2 之类）
#   - dxvk/vkd3d 没被加载（D3D10CoreCreateDevice@20, aborting）
#
# 用法：
#   ./wine-dxvk-launch.sh <游戏.exe> [分辨率] [WINEPREFIX]
#   ./wine-dxvk-launch.sh game.exe 1280x720 /data/data/com.termux/files/home/.wine
set -u

GAME="${1:-}"
RES="${2:-1280x720}"
PREFIX="${3:-${WINEPREFIX:-${HOME}/.wine}}"

if [ -z "$GAME" ]; then
  echo "用法: $0 <游戏.exe> [分辨率 如 1280x720] [WINEPREFIX]" >&2
  exit 1
fi

if [ ! -f "$GAME" ]; then
  echo "找不到游戏文件: $GAME" >&2
  exit 1
fi

export WINEPREFIX="$PREFIX"

# ---- DLL 覆盖：dxvk(d3d8/9/10core/11/dxgi) + vkd3d-proton(d3d12) ----
export WINEDLLOVERRIDES="d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core=n,b"

# ---- 日志（排查时打开，稳定后可注释）----
# export DXVK_LOG_LEVEL=debug
# export DXVK_LOG_PATH="$(dirname "$GAME")/dxvk-logs"
# export DXVK_HUD=api,devinfo,fps

echo "[info] WINEPREFIX=$WINEPREFIX"
echo "[info] 虚拟桌面=$RES（固定尺寸，避免退化交换链）"
echo "[info] override=$WINEDLLOVERRIDES"
echo "[info] 启动: $GAME"

# 用固定尺寸的虚拟桌面启动；/desktop 会把所有窗口固定到该分辨率
exec wine explorer "/desktop=dxvk,$RES" "$GAME" "${@:4}"

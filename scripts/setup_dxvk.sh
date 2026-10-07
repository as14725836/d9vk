#!/usr/bin/env bash
# setup_dxvk.sh — 通用 DXVK / vkd3d-proton 安装脚本
#
# 上游 dxvk 从 3.x 起删除了自带的 setup_dxvk.sh，本脚本用来填补这个缺口，
# 且对 1.x / 2.x / vkd3d-proton 的包同样适用。
#
# 用法：
#   ./setup_dxvk.sh <包目录> [WINEPREFIX]            安装
#   ./setup_dxvk.sh --uninstall [WINEPREFIX]         恢复被覆盖的原文件
#
# 包目录结构：
#   带 x64/ 与 x86/（或 x32/）子目录  → 自动按位数安装（本仓库发布的包都是这样）
#   直接放 dll                      → 用 --64 或 --32 指定位数
set -u

info() { echo "[*] $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[x] $*" >&2; exit 1; }

MODE=install
PKG=""
BIT=""
PREFIX="${WINEPREFIX:-}"

if [ "${1:-}" = "--uninstall" ]; then
  MODE=uninstall
  PREFIX="${2:-$PREFIX}"
else
  PKG="${1:-}"
  case "${2:-}" in
    "") ;;
    --64|--32) ;;          # 第 2 个参数是位数开关，PREFIX 仍用环境变量
    *) PREFIX="$2" ;;
  esac
  case "${2:-}" in --64) BIT=x64 ;; --32) BIT=x86 ;; esac
  case "${3:-}" in --64) BIT=x64 ;; --32) BIT=x86 ;; esac
fi

[ -n "$PREFIX" ] || die "未指定 WINEPREFIX（也没设置环境变量 WINEPREFIX）"
[ -d "$PREFIX/drive_c/windows" ] || die "$PREFIX 看起来不是 Wine 前缀（没找到 drive_c/windows）"
SYS32="$PREFIX/drive_c/windows/system32"
SYSWOW="$PREFIX/drive_c/windows/syswow64"
BAK=.dxvk-bak

if [ "$MODE" = uninstall ]; then
  n=0
  for dst in "$SYS32" "$SYSWOW"; do
    [ -d "$dst" ] || continue
    for f in "$dst"/*.dll"$BAK"; do
      [ -e "$f" ] || continue
      mv -f "$f" "${f%$BAK}" && n=$((n + 1))
    done
  done
  info "已恢复 $n 个备份文件"
  exit 0
fi

[ -n "$PKG" ] || die "未指定包目录"
[ -d "$PKG" ] || die "包目录不存在：$PKG"

install_dir() {
  src="$1"; dst="$2"; cnt=0
  [ -d "$src" ] || { echo 0; return 0; }
  [ -d "$dst" ] || mkdir -p "$dst"
  for f in "$src"/*.dll; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if [ -e "$dst/$name" ] && [ ! -e "$dst/$name$BAK" ]; then
      cp -p "$dst/$name" "$dst/$name$BAK"
    fi
    cp -f "$f" "$dst/" || die "拷贝失败：$f"
    cnt=$((cnt + 1))
  done
  echo "$cnt"
}

TOTAL=0
if [ -d "$PKG/x64" ] || [ -d "$PKG/x86" ] || [ -d "$PKG/x32" ]; then
  n1=$(install_dir "$PKG/x64" "$SYS32"); n1=${n1:-0}
  n2=$(install_dir "$PKG/x86" "$SYSWOW"); n2=${n2:-0}
  if [ "$n2" = 0 ]; then n2=$(install_dir "$PKG/x32" "$SYSWOW"); n2=${n2:-0}; fi
  TOTAL=$((n1 + n2))
  info "x64 → system32：$n1 个；x86 → syswow64：$n2 个"
else
  [ -n "$BIT" ] || die "包目录里没有 x64/x86 子目录，请加 --64 或 --32 指定位数"
  if [ "$BIT" = x64 ]; then TOTAL=$(install_dir "$PKG" "$SYS32"); else TOTAL=$(install_dir "$PKG" "$SYSWOW"); fi
  TOTAL=${TOTAL:-0}
  info "$BIT → 已安装 $TOTAL 个 DLL"
fi

[ "$TOTAL" -gt 0 ] || die "没有找到任何 .dll，包目录对吗？"

DLLS=$(ls "$PKG/x64"/*.dll "$PKG/x86"/*.dll "$PKG/x32"/*.dll 2>/dev/null | sed 's|.*/||' | sed 's|[.]dll$||' | sort -u | paste -sd, -)
if [ -z "$DLLS" ]; then DLLS=d3d8,d3d9,d3d10core,d3d11,dxgi,d3d12,d3d12core; fi

info "安装完成：共 $TOTAL 个 DLL"
echo
echo "还需要让 Wine 优先用这些 DLL（native 覆盖 builtin）："
echo "  export WINEDLLOVERRIDES=${DLLS}=n,b"
echo
echo "可选：在游戏目录或 WINEPREFIX 下放 dxvk.conf，常用项："
echo "  dxgi.maxFrameLatency = 1"
echo "  d3d9.maxFrameLatency = 1"
echo "  d3d9.presentInterval = 1"
echo "  d3d9.enumerateByDisplays = False     # 避免拿到奇怪的显示模式（如 185x2）"
echo "  黑屏/偏色/分辨率异常/D3D10CoreCreateDevice@20 aborting → 见 docs/COMPATIBILITY.md"
echo
echo "恢复原状：$0 --uninstall $PREFIX"

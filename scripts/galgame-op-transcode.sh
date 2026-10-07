#!/usr/bin/env bash
# galgame-op-transcode.sh — 把 galgame 的 OP/ED 视频转小，降低解码负担
#
# 背景：Wine 下视频解码是 CPU 干的（DirectShow/quartz 或 mfplat + 解码器 DLL），
# 在 box64 环境里那些 DLL 是 x86 代码、被翻译后执行。解码代价与
# “分辨率 x 帧率 x 编码复杂度”成正比，所以“转小”是最确定有效的办法。
#
# 安全设计：默认只打印将要执行的命令，不动任何文件；输出到 <原目录>/out/，
# 不覆盖原文件。
#
# 用法：
#   ./galgame-op-transcode.sh <视频文件> [宽度] [帧率] [--run]
#   ./galgame-op-transcode.sh movie/op.wmv 640 15 --run
set -u

SRC="${1:-}"
W="${2:-640}"
FPS="${3:-15}"
RUN=0
for a in "$@"; do if [ "$a" = "--run" ]; then RUN=1; fi; done

if [ -z "$SRC" ]; then echo "用法: $0 <视频文件> [宽度=640] [帧率=15] [--run]" >&2; exit 1; fi
if [ ! -f "$SRC" ]; then echo "文件不存在：$SRC" >&2; exit 1; fi
if ! command -v ffmpeg >/dev/null 2>&1; then echo '未找到 ffmpeg' >&2; exit 1; fi

DIR=$(dirname "$SRC")
BASE=$(basename "$SRC")
EXT=$(printf '%s' "${BASE##*.}" | tr 'A-Z' 'a-z')
OUTDIR="$DIR/out"
mkdir -p "$OUTDIR"
STEM="${BASE%.*}"

# 按扩展名选编码器：容器与扩展名保持不变，只降低分辨率/帧率
VCODEC=""
OUT="$OUTDIR/$BASE"
case "$EXT" in
  wmv|asf) VCODEC="-c:v wmv2 -b:v 1500k"; OUT="$OUTDIR/$STEM.wmv" ;;
  mpg|mpeg) VCODEC="-c:v mpeg2video -b:v 2000k"; OUT="$OUTDIR/$STEM.mpg" ;;
  avi) VCODEC="-c:v mjpeg -q:v 5"; OUT="$OUTDIR/$STEM.avi" ;;
  mp4|m4v) VCODEC="-c:v mpeg4 -q:v 5 -movflags +faststart"; OUT="$OUTDIR/$STEM.mp4" ;;
  *) VCODEC="-c:v mjpeg -q:v 5"; echo "[!] 未知扩展名 .$EXT，默认用 MJPEG 输出到 $OUT" ;;
esac

echo "[*] 原文件: $SRC ($(du -h "$SRC" 2>/dev/null | cut -f1))"
echo "[*] 输出到: $OUT"
echo "[*] 参数: 宽=$W 帧率=$FPS 编码=$VCODEC"
echo "[*] 将执行:"
echo "    ffmpeg -y -i '$SRC' -vf scale=$W:-2:flags=fast_bilinear,fps=$FPS $VCODEC -c:a copy '$OUT'"

if [ "$RUN" != "1" ]; then
  echo
  echo "（未执行。确认后加 --run；替换前请先备份原文件。）"
  exit 0
fi

exec ffmpeg -y -i "$SRC" -vf "scale=${W}:-2:flags=fast_bilinear,fps=${FPS}" $VCODEC -c:a copy "$OUT"

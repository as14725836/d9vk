#!/usr/bin/env bash
# android-mem-tune.sh — Android 内核参数检查 / 调优（需要 root）
#
# Wine + box64 会做大量 mmap，Android 默认的 vm.max_map_count 偏低，
# 常见表现是“突然 Cannot allocate memory”或莫名其妙崩退。
#
# 用法：
#   ./android-mem-tune.sh           只打印当前值（不需要 root）
#   ./android-mem-tune.sh --apply   写入推荐值（需要 root）
set -u
SH=su
[ "$(id -u)" = 0 ] || { command -v su >/dev/null || { echo '需要 root（su 不存在）' >&2; exit 1; }; }

read_one() { $SH -c "cat /proc/sys/$1" 2>/dev/null || echo '(读不到)'; }
write_one() { $SH -c "echo $2 > /proc/sys/$1" 2>/dev/null && echo "  $1 → $2" || echo "  $1 写入失败（无权限）"; }

echo '=== 当前值 ==='
for k in vm/max_map_count vm/swappiness vm/min_free_kbytes; do echo "  $k = $(read_one $k)"; done
echo '=== 内存 ==='
grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo | sed 's/^/  /'

if [ "${1:-}" != '--apply' ]; then
  echo
  echo '（只需看的话到此为止；要写入推荐值请加 --apply）'
  echo '推荐：vm.max_map_count >= 262144，vm.swappiness 保持 100（zram 场景）'
  exit 0
fi

echo '=== 应用推荐值 ==='
write_one vm/max_map_count 262144
write_one vm/swappiness 100
echo '注意：max_map_count 重启后会恢复，需要持久化请用 Magisk/开机脚本。'

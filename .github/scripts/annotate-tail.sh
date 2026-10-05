#!/usr/bin/env bash
# 失敗時に、ログの末尾を ::error:: 注釈として出す（Actions の画面やチェックの注釈 API から読めるように）
#   annotate-tail.sh <行数> <ファイル...>
set -uo pipefail
n=${1:-40}; shift
for f in "$@"; do
  [ -s "$f" ] || continue
  msg=$(tail -n "$n" "$f" | cut -c1-300 | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=$(basename "$f") の末尾 ${n} 行::${msg}"
done
exit 0

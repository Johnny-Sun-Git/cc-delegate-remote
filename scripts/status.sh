#!/usr/bin/env bash
# 查一个索引文件夹对应的最近一次后台任务(start-bg.sh 起的)跑得怎么样了。
# 用法: status.sh <索引文件夹>
set -euo pipefail
caller_cwd="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./lib.sh

folder="${1:?用法: status.sh <索引文件夹>}"
[[ "$folder" == /* ]] || folder="$caller_cwd/$folder"
dr_read_index "$folder"

f="$folder/.delegate.json"
pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("last_run",{}).get("pid",""))' "$f")"
result_path="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("last_run",{}).get("result_path",""))' "$f")"

if [[ -z "$pid" ]]; then
  echo "这个索引文件夹还没用 start-bg.sh 起过后台任务。" >&2
  exit 1
fi

if ssh "$HOST" "kill -0 $pid 2>/dev/null"; then
  echo "还在跑(host=$HOST pid=$pid)"
  exit 2
fi

echo "已结束(host=$HOST pid=$pid)"
if content="$(ssh "$HOST" "cat $(printf %q "$result_path") 2>/dev/null")" && [[ -n "$content" ]]; then
  echo "$content"
else
  echo "结果文件还没写出来,或者任务异常退出没留下结果——看 $HOST:$(dirname "$result_path")/.stderr.log" >&2
  exit 1
fi

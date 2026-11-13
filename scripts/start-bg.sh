#!/usr/bin/env bash
# 把一个长时间/开放式任务,起成远端(索引文件夹对应的那台机器)上的后台进程,立即返回,不阻塞本地。
#
# 踩坑记录: 别用 claude 自带的 `--bg`——实测它只会建一个空的交互式会话等你 attach 进去打字,
# 不会把跟在后面的 prompt 当成任务自动跑起来;`--bg --resume <id>` 想塞任务进去,会分裂出一个新会话。
# 这里改用最朴实、已验证过的办法: 把 `-p`(非交互单次调用)用 nohup+setsid 甩到远端后台,输出写文件,
# 用进程是否存在 + 结果文件是否出现来判断有没有跑完。
#
# prompt 从 stdin 读入,同样走文件传输,避免引号地狱。
#
# 用法: start-bg.sh <索引文件夹> <任务名> [profile 覆盖] [额外 --add-dir 目录...] < prompt.txt
# 跑起来之后,状态/结果记在索引文件夹的 .delegate.json 里的 last_run 字段,配合 status.sh 查。
set -euo pipefail
caller_cwd="$PWD"   # 必须在 cd 之前记下来,因为 <索引文件夹> 很可能是相对于调用者 cwd 的相对路径
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./lib.sh
start_timeout_s="${DR_START_TIMEOUT:-60}"   # 只守"把进程甩到后台"这个动作本身,不是任务跑多久

folder="${1:?用法: start-bg.sh <索引文件夹> <任务名> [profile] [额外目录...] < prompt.txt}"
[[ "$folder" == /* ]] || folder="$caller_cwd/$folder"
name="${2:?缺少任务名}"
shift 2
profile_override="${1:-}"; [[ $# -gt 0 ]] && shift || true
extra_dirs=("$@")

dr_read_index "$folder"
profile="$(dr_resolve_profile "$HOST" "$profile_override" "$IDX_PROFILE")"
dr_cfg has-profile "$HOST" "$profile" || exit 1
bin="$(dr_cfg get-bin "$HOST" "$profile")"
mapfile -t model_args < <(dr_cfg get-args "$HOST" "$profile")

add_dir_q=$(printf ' --add-dir %q' "$REMOTE_DIR" "${extra_dirs[@]:-}")

dr_sync_claude_md_chain "$folder"
dr_upload_prompt "$HOST" "$REMOTE_DIR"

# --permission-mode 必须显式给: ccr 类工具不传会自己补 --dangerously-skip-permissions(无约束);
# 也别用 plan 模式——没人盯着的后台调用用 plan 会要求人工批准计划,会永远卡住。
out=$(timeout "$start_timeout_s" ssh "$HOST" bash -ls <<REMOTE
set -euo pipefail
cd $(printf %q "$REMOTE_DIR")
PROMPT="\$(cat .prompt.txt)"
nohup setsid $bin -p "\$PROMPT" \
  ${model_args[@]+"${model_args[@]}"} \
  --permission-mode acceptEdits \
  --permission-prompts none \
  --output-format json \
  $add_dir_q \
  > .raw.out 2> .stderr.log < /dev/null &
echo "PID=\$!"
disown
REMOTE
)
pid="$(grep -oE 'PID=[0-9]+' <<<"$out" | head -1 | cut -d= -f2)"
[[ -n "$pid" ]] || { echo "起后台进程失败: $out" >&2; exit 1; }

# 另起一个极短命令,等输出真正落地后,从 .raw.out 里把干净的结果行抽到 .result.json(异步做,不阻塞这里返回)
ssh "$HOST" bash -ls <<REMOTE >/dev/null 2>&1 &
set -e
cd $(printf %q "$REMOTE_DIR")
while kill -0 "$pid" 2>/dev/null; do sleep 2; done
grep -E '^\{"duration_api_ms"' .raw.out | tail -n1 > .result.json || true
REMOTE
disown

python3 -c '
import json, sys
f, pid, name, remote_dir = sys.argv[1:5]
try:
    d = json.load(open(f))
except FileNotFoundError:
    d = {}
d["last_run"] = {"pid": pid, "name": name, "result_path": remote_dir + "/.result.json",
                  "stderr_path": remote_dir + "/.stderr.log"}
json.dump(d, open(f, "w"), ensure_ascii=False, indent=2)
' "$folder/.delegate.json" "$pid" "$name" "$REMOTE_DIR"

echo "PID=$pid NAME=$name"
echo "查进度: $DR_SELF_DIR/status.sh $folder"

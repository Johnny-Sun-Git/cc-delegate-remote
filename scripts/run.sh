#!/usr/bin/env bash
# 把一个有边界、能同步等结果的任务,一次性交给索引文件夹对应的远端 Claude Code 跑完。
# prompt 从 stdin 读入(任意引号/换行/反引号都安全,走文件传输,不走字符串拼接)。
#
# 用法: run.sh <索引文件夹> [profile 覆盖] [额外 --add-dir 目录...] < prompt.txt
# 输出: 单行 JSON(到 stdout,已过滤掉可能混进来的非 JSON 诊断行),解析用 .result / .is_error / .total_cost_usd
# 超时(秒)可用环境变量 DR_RUN_TIMEOUT 覆盖,默认 600。
set -euo pipefail
caller_cwd="$PWD"   # 必须在 cd 之前记下来,因为 <索引文件夹> 很可能是相对于调用者 cwd 的相对路径
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./lib.sh
timeout_s="${DR_RUN_TIMEOUT:-600}"

folder="${1:?用法: run.sh <索引文件夹> [profile] [额外目录...] < prompt.txt}"
[[ "$folder" == /* ]] || folder="$caller_cwd/$folder"
shift
profile_override="${1:-}"; [[ $# -gt 0 ]] && shift || true
extra_dirs=("$@")

dr_read_index "$folder"
profile="$(dr_resolve_profile "$HOST" "$profile_override" "$IDX_PROFILE")"
dr_cfg has-profile "$HOST" "$profile" || exit 1
bin="$(dr_cfg get-bin "$HOST" "$profile")"
mapfile -t model_args < <(dr_cfg get-args "$HOST" "$profile")

add_dir_q=$(printf ' --add-dir %q' "$REMOTE_DIR" "${extra_dirs[@]:-}")

# 0) 把本地这条索引链(从这一级到 host 根)上的 CLAUDE.md 同步到远端对应目录,
#    这样远端 Claude Code 启动时沿目录树往上走会自动叠加读到整条链的资产/边界说明。
dr_sync_claude_md_chain "$folder"

# 1) 把 prompt 原样传过去,走纯字节流,不经过任何 shell 解释
dr_upload_prompt "$HOST" "$REMOTE_DIR"

# 2) 远端执行: heredoc 里只插入我们自己生成、安全可控的值(REMOTE_DIR/bin/model_args/add_dir_q),
#    prompt 本身永远不出现在这段文本里,而是在远端运行时从文件读出来,躲开引号地狱。
#    timeout 包一层防止网关挂住时无限等;最后 grep 只留真正的结果行(有些后端会在 JSON 前混一行诊断文本)。
# claude 进程在报 is_error:true 的 API 错误时,自身退出码也可能是非 0——那也是一次"跑完了、有结果"的调用,
# 不该被下面 set -e 直接杀掉脚本,所以这里用 `|| true` 接住,只看 $result 里到底有没有拿到那行 JSON。
result="$(timeout "$timeout_s" ssh "$HOST" bash -ls <<REMOTE | grep -E '^\{"duration_api_ms"' | tail -n1
set -euo pipefail
cd $(printf %q "$REMOTE_DIR")
PROMPT="\$(cat .prompt.txt)"
$bin -p "\$PROMPT" \
  ${model_args[@]+"${model_args[@]}"} \
  --permission-mode acceptEdits \
  --permission-prompts none \
  --output-format json \
  $add_dir_q
REMOTE
)" || true
echo "$result"

# 3) 本地索引文件夹只记一行摘要(时间/profile/是否出错),不抄远端的完整内容
status_rc=1
summary="(未拿到可解析的结果,见上面的 timeout/ssh 报错)"
if [[ -n "$result" ]]; then
  summary="$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print((("ERROR" if d.get("is_error") else "OK")) + "|" + str(d.get("result",""))[:200].replace(chr(10), " "))
sys.exit(1 if d.get("is_error") else 0)
' "$result")" && status_rc=0 || status_rc=1
  [[ -n "$summary" ]] || summary="(结果不是合法 JSON,见上面的输出)"
fi
printf -- '\n- %s  [%s]  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$profile" "$summary" >> "$folder/task.md"
exit "$status_rc"

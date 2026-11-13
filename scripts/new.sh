#!/usr/bin/env bash
# 建一条嵌套的索引文件夹链(在当前目录下),顺带在远端建好每一级对应的目录。
# 支持任意深度,比如 <host>/<task-group>/<task>/<subtask>;已存在的上级会被复用、往下继承,
# 不会重新创建或覆盖已有内容。每一级都会有 .delegate.json(host/远端目录/profile)、
# CLAUDE.md(这一级的资产/边界说明,模板留空等你填)、task.md(这一级的运行日志)。
#
# 用法: new.sh <host> <seg1> [seg2] [seg3] ... [--profile 名字]
#   --profile 只作用于本次调用新建的"最深那一级",之上的每一级(包括已存在的祖先)不受影响;
#   不传就从直接上级继承 profile,顶层(host 本身)没有上级时,用 hosts.json 里的 default_profile。
set -euo pipefail
caller_cwd="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./lib.sh

[[ $# -ge 1 ]] || { echo "用法: new.sh <host> <seg1> [seg2] ... [--profile 名字]" >&2; exit 1; }
host="$1"; shift
profile_override=""
segs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) profile_override="${2:?--profile 后面要跟一个值}"; shift 2 ;;
    *) segs+=("$1"); shift ;;
  esac
done
for s in "${segs[@]}"; do
  [[ "$s" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo "路径段只能用字母/数字/./_/-,收到: $s" >&2; exit 1; }
done

dr_cfg has-host "$host" || exit 1
[[ -z "$profile_override" ]] || dr_cfg has-profile "$host" "$profile_override" || exit 1

claude_md_template() {
  local level_desc="$1" is_root="$2"
  if [[ "$is_root" == 1 ]]; then
    cat <<'EOF'
## 这台机器的资产/边界

(系统类型、共享存储、配额、你能读写的范围、有什么已知限制——写在这里,下面所有层级都会自动继承,别在下面重复。)
EOF
  else
    cat <<EOF
## $level_desc 这一级的补充说明

(只写"比上一级更具体"的信息。上一级的资产/边界说明会由 Claude Code 自动一起加载,不用在这里重复抄。)
EOF
  fi
}

# --- 第 0 级: host 本身 ---
level_dir="$caller_cwd/$host"
if [[ -f "$level_dir/.delegate.json" ]]; then
  dr_read_index "$level_dir"
  cur_profile="${IDX_PROFILE:-$(dr_cfg get-default-profile "$host")}"
  cur_remote_dir="$REMOTE_DIR"
  echo "已存在: $level_dir"
else
  cur_remote_dir="$(dr_cfg get-remote-root "$host")"
  cur_profile="$(dr_cfg get-default-profile "$host")"
  [[ ${#segs[@]} -eq 0 && -n "$profile_override" ]] && cur_profile="$profile_override"
  mkdir -p "$level_dir"
  ssh "$host" "mkdir -p -- $(printf %q "$cur_remote_dir")"
  python3 -c '
import json, sys
f, host, remote_dir, profile = sys.argv[1:5]
json.dump({"host": host, "remote_dir": remote_dir, "profile": profile}, open(f, "w"), ensure_ascii=False, indent=2)
' "$level_dir/.delegate.json" "$host" "$cur_remote_dir" "$cur_profile"
  claude_md_template "$host" 1 > "$level_dir/CLAUDE.md"
  printf '# %s\n\n(这台机器的笔记,非必需,主要资产说明写 CLAUDE.md)\n' "$host" > "$level_dir/task.md"
  echo "新建: $level_dir"
fi

# --- 逐级往下 ---
last_idx=$(( ${#segs[@]} - 1 ))
for i in "${!segs[@]}"; do
  seg="${segs[$i]}"
  parent_dir="$level_dir"
  level_dir="$parent_dir/$seg"
  remote_dir="$cur_remote_dir/$seg"
  if [[ -f "$level_dir/.delegate.json" ]]; then
    HOST="" REMOTE_DIR="" IDX_PROFILE=""
    dr_read_index "$level_dir"
    cur_profile="${IDX_PROFILE:-$cur_profile}"
    cur_remote_dir="$REMOTE_DIR"
    echo "已存在: $level_dir"
  else
    [[ "$i" == "$last_idx" && -n "$profile_override" ]] && cur_profile="$profile_override"
    mkdir -p "$level_dir"
    ssh "$host" "mkdir -p -- $(printf %q "$remote_dir")"
    python3 -c '
import json, sys
f, host, remote_dir, profile = sys.argv[1:5]
json.dump({"host": host, "remote_dir": remote_dir, "profile": profile}, open(f, "w"), ensure_ascii=False, indent=2)
' "$level_dir/.delegate.json" "$host" "$remote_dir" "$cur_profile"
    claude_md_template "$seg" 0 > "$level_dir/CLAUDE.md"
    printf '# %s\n\n- host: `%s`\n- 远端目录: `%s`\n- 创建时间: %s\n\n## 目标\n\n(写清楚这一级要做什么)\n\n## 索引(只放指针,别把远端内容抄过来)\n\n- 远端 prompt/结果: `%s/.prompt.txt` / `%s/.result.json`\n' \
      "$seg" "$host" "$remote_dir" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$remote_dir" "$remote_dir" > "$level_dir/task.md"
    cur_remote_dir="$remote_dir"
    echo "新建: $level_dir"
  fi
done

echo "---"
echo "可以用了: $level_dir"
echo "远端目录: $cur_remote_dir"
echo "先编辑一下这条链上每一级的 CLAUDE.md,再开始 run.sh / start-bg.sh"

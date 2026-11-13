#!/usr/bin/env bash
# 建一条嵌套的索引文件夹链(在当前目录下),顺带在远端建好每一级对应的目录。
# 支持任意深度,比如 <host>/<task-group>/<task>,不强求都要建到底——host 单独一级,
# 或 host+一级任务,很多情况下就够。已存在的上级会被复用、往下继承,不会重新创建或覆盖已有内容。
# 每一级只有两个文件: .delegate.json(host/远端目录/profile,机器用) 和 CLAUDE.md(只放用户
# 意图,不放探测到的具体命令/路径——那些会过时,需要时重新问远端,不要当成永久记忆,也不要
# 在本地攒运行日志之类会越写越多的东西;最新的运行结果永远看远端的 .result.json 就够)。
# 建好之后,通常接着用 Edit 把探测后聊出来的"用户意图"写进对应那一级的 CLAUDE.md。
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
    # 操作说明只在 host 根这一级写一次(下面每一级被加载时都会带着它,不用重复)。
    # 下面"用户意图"这部分才是人要编辑的内容;操作说明部分是骨架自带的,不属于"意图",别删。
    cat <<'EOF'
<!-- 以下是 delegate-remote 骨架自带的操作说明,不是用户意图,正常不需要改动 -->

在这棵目录树下工作时的默认方式:
- 这个文件夹对应远端某台机器的某个目录(见 `.delegate.json`)。想知道远端现在实际是什么样
  (文件是否存在、内容是什么、命令输出是什么),直接 `ssh <host> '...'` 问一下,不要凭记忆猜,
  也不要把问到的结果当成这里要记下来的东西——远端会变,这里只记"想要什么",不记"现在是什么"。
- 只有当一件事**必须落在远端**(改远端的文件、跑远端的命令/测试),且这件事小到能一句话说清楚时,
  才用 `scripts/run.sh`(一次性)或 `scripts/start-bg.sh`(长任务)委派出去。别把"整个任务"
  一股脑扔过去让对面自己判断怎么做——规划和判断留在本地这边做,委派出去的应该是边界清楚的单步操作。
- 纯只读的查询不需要走委派脚本,直接 ssh 问就行,没必要为了看一眼文件去调一次远端的 Claude Code。

<!-- 以上是骨架自带的,下面才是你编辑的部分 -->

## 用户意图

(这台机器上,你希望任务整体往什么方向做、有什么边界/禁区——写在这里,下面所有层级都会继承这段,
不用在更深的层级重复。)
EOF
  else
    cat <<EOF
## 用户意图($level_desc 这一级,只补充比上一级更具体的部分)

(上一级的意图会自动一起加载,这里不用重复抄;没有额外要补充的,留空也行。)
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
    cur_remote_dir="$remote_dir"
    echo "新建: $level_dir"
  fi
done

echo "---"
echo "可以用了: $level_dir"
echo "远端目录: $cur_remote_dir"
echo "先编辑一下这条链上每一级的 CLAUDE.md,再开始 run.sh / start-bg.sh"

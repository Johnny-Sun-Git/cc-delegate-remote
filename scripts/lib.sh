#!/usr/bin/env bash
# 被其它脚本 source,不单独运行。
set -euo pipefail

DR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DR_CFG_PY="$DR_SELF_DIR/_cfg.py"
DR_CONFIG="${DELEGATE_REMOTE_CONFIG:-$HOME/.config/delegate-remote/hosts.json}"

dr_cfg() { python3 "$DR_CFG_PY" "$DR_CONFIG" "$@"; }

# 读取索引文件夹 <folder>/.delegate.json,把结果写进调用者的 HOST / REMOTE_DIR / IDX_PROFILE 变量
# (要求调用处已经 declare 过这三个变量,或者直接在顶层脚本里用,不是函数内部)
dr_read_index() {
  local folder="$1" f="$1/.delegate.json"
  [[ -f "$f" ]] || { echo "找不到索引文件: $f(这个文件夹不是用 new.sh 建的?)" >&2; exit 1; }
  local out
  out="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("host", ""))
print(d.get("remote_dir", ""))
print(d.get("profile", ""))
' "$f")"
  HOST="$(sed -n 1p <<<"$out")"
  REMOTE_DIR="$(sed -n 2p <<<"$out")"
  IDX_PROFILE="$(sed -n 3p <<<"$out")"
  [[ -n "$HOST" && -n "$REMOTE_DIR" ]] || { echo "索引文件损坏: $f" >&2; exit 1; }
}

# 把 <folder>/.delegate.json 里某个顶层字段设置成给定值(简单的、不存在就新建、存在就覆盖)
dr_write_index_field() {
  local folder="$1" key="$2" value="$3" f="$1/.delegate.json"
  python3 -c '
import json, sys
f, key, value = sys.argv[1:4]
try:
    d = json.load(open(f))
except FileNotFoundError:
    d = {}
d[key] = value
json.dump(d, open(f, "w"), ensure_ascii=False, indent=2)
' "$f" "$key" "$value"
}

# 解析 profile: 显式传入 > 索引文件里记的 > host 的 default_profile
dr_resolve_profile() {
  local host="$1" explicit="${2:-}" idx="${3:-}"
  if [[ -n "$explicit" ]]; then echo "$explicit"
  elif [[ -n "$idx" ]]; then echo "$idx"
  else dr_cfg get-default-profile "$host"
  fi
}

# 把 prompt(从 stdin 读)安全地传到远端 <host>:<dir>/.prompt.txt,不经过任何 shell 转义
dr_upload_prompt() {
  local host="$1" dir="$2"
  ssh "$host" "mkdir -p -- $(printf %q "$dir") && cat > $(printf %q "$dir")/.prompt.txt"
}

# 把 <folder> 到"host 根"这条链上、每一级的 CLAUDE.md 同步到远端对应目录(文件不存在就跳过)。
# 本地是资产文档的编写处(会被 git 追踪、可分享),远端只是镜像——这样远端 Claude Code 启动时,
# 沿目录树往上走会自动叠加读到整条链的资产/边界说明,不用自己写继承逻辑。
# 要求 <folder> 本身及它的每一级祖先目录都有 .delegate.json(new.sh 建的时候就会写),
# 一旦某一级没有 .delegate.json,就说明已经走出了这套索引文件夹的管理范围,到此为止。
dr_sync_claude_md_chain() {
  local folder="$1" dir="$folder" h rd
  while [[ -f "$dir/.delegate.json" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      read -r h rd < <(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("host",""), d.get("remote_dir",""))
' "$dir/.delegate.json" 2>/dev/null || true) || true
      h="${h:-}"; rd="${rd:-}"
      if [[ -n "$h" && -n "$rd" ]]; then
        ssh "$h" "mkdir -p -- $(printf %q "$rd") && cat > $(printf %q "$rd")/CLAUDE.md" < "$dir/CLAUDE.md"
      fi
    fi
    local parent; parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && break   # 到文件系统根了,保险起见退出
    dir="$parent"
  done
}

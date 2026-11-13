#!/usr/bin/env bash
# 新建一个"服务器名-任务名"索引文件夹(在当前目录下),并在远端建好对应的任务目录。
# 用法: new.sh <host> <task-slug> [profile]
#   host       — hosts.json 里配置过的别名(不是 ssh 本身的配置,是这个 skill 自己的 host 配置)
#   task-slug  — 任务短标识,会拼进文件夹名和远端路径,建议小写+短横线
#   profile    — 可选,不传就用这个 host 的 default_profile,后面随时能在 .delegate.json 里改
set -euo pipefail
caller_cwd="$PWD"   # 必须在任何 cd 之前记下来,后面本地索引文件夹要建在调用者当时所在的目录
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./lib.sh

host="${1:?用法: new.sh <host> <task-slug> [profile]}"
slug="${2:?缺少 task-slug}"
profile="${3:-}"

[[ "$slug" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo "task-slug 只能用字母/数字/./_/-,收到: $slug" >&2; exit 1; }
dr_cfg has-host "$host" || exit 1
[[ -z "$profile" ]] || dr_cfg has-profile "$host" "$profile" || exit 1

remote_root="$(dr_cfg get-remote-root "$host")"
remote_dir="$remote_root/$slug"
local_dir="$caller_cwd/${host}-${slug}"

[[ -e "$local_dir" ]] && { echo "本地索引文件夹已存在: $local_dir" >&2; exit 1; }

ssh "$host" "mkdir -p -- $(printf %q "$remote_dir")"

mkdir -p "$local_dir"
python3 -c '
import json, sys
f, host, remote_dir, profile = sys.argv[1:5]
d = {"host": host, "remote_dir": remote_dir}
if profile:
    d["profile"] = profile
json.dump(d, open(f, "w"), ensure_ascii=False, indent=2)
' "$local_dir/.delegate.json" "$host" "$remote_dir" "$profile"

cat > "$local_dir/task.md" <<EOF
# ${host}-${slug}

- host: \`$host\`
- 远端目录: \`$remote_dir\`
- 创建时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## 目标

(写清楚这个任务要做什么,范围是什么)

## 状态

尚未开始。

## 索引(只放指针,别把远端内容抄过来)

- 远端 prompt/结果: \`$remote_dir/.prompt.txt\` / \`$remote_dir/.result.json\`
- 查看: \`ssh $host "cat $remote_dir/.result.json"\`
EOF

echo "建好了: $local_dir"
echo "远端目录: $remote_dir"

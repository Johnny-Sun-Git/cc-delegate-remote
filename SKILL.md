---
name: delegate-remote
description: Delegate a bounded or long-running dev/test task to a Claude Code instance running on a different machine, for anything whose correctness depends on that machine's local state — its files, running processes, build tools, GPU/hardware, or anything that machine's own CLAUDE.md/AGENTS.md governs. This session's own Read/Edit/Write/Grep/Glob tools only see this machine's filesystem and cannot reach any other host at all; a raw `ssh <host> '...'` one-liner works for a single read-only probe but is the wrong tool for anything needing multi-step judgment, file edits, or a build/test loop on that machine. Use this skill instead whenever the real work has to happen on another host, and whenever you're tracking work across several hosts and/or several task directories on the same host — it gives each (host, task) pair its own local index folder instead of juggling raw ssh commands and remembered paths.
---

# delegate-remote

一个机制:把任务整体交给**另一台机器自己的 Claude Code**去做,而不是试图在本地模拟远程文件操作。
一个约定:每个(服务器,任务)配一个本地**索引文件夹**,文件夹名是 `<host>-<task-slug>`,夹子里**只放指针**(去哪台机器、哪个远端目录、用哪个模型/命令),不放实际代码或数据——真正的工作永远留在远端。

## 什么时候用,什么时候不用

- 这个会话的 Read/Edit/Write/Grep/Glob/NotebookEdit 全都只能碰本机文件系统,完全看不到别的主机。想对另一台机器上的文件做任何实质性的事(改代码、跑测试、编译),都不能用这些工具硬凑,要走这个 skill。
- 只是一次性、只读的探测(查一下文件在不在、看一眼日志),直接 `ssh <host> '...'` 就行,不用走这个 skill。
- 目标机器**必须已经有自己配置好的 Claude Code**(装了 `claude` 或等价的命令行入口,能认得 `-p`/`--output-format json`/`--permission-mode` 这类参数)。这个 skill 不负责在远端安装或配置 Claude Code 本身。

## 第一次用:配置

1. 复制 `hosts.example.json` 到 `~/.config/delegate-remote/hosts.json`(这份文件**不要**提交到任何公开仓库,里面是你自己的机器/模型信息)。
2. 按你自己的情况填每个 host:
   - `remote_task_root`:这台机器上,给委派任务用的一个工作根目录(比如 `/home/you/tasks`)。
   - `profiles`:这台机器上有哪些可用的"调用方式",每个 profile 是 `{"bin": "命令名", "args": [...]}`,`bin` 必须接受 Claude Code 风格的参数(`-p "<prompt>" --permission-mode X --permission-prompts none --output-format json --add-dir Y`,以及不带 `-p` 时接受位置参数 prompt)。常见情况: `claude` 本身,或者某个路由到别的模型的包装命令(比如 `claude-ccr --model xxx`)。
   - `default_profile`:不指定 profile 时用哪个。
3. (可选)想把配置放在别处,设环境变量 `DELEGATE_REMOTE_CONFIG=/path/to/hosts.json`。

## 日常用法

```bash
S=~/.claude/skills/delegate-remote/scripts

# 1) 新建一个索引文件夹(在当前目录下建 <host>-<task-slug>,同时在远端建好对应目录)
$S/new.sh internal fix-symm-mem-oom
cd internal-fix-symm-mem-oom

# 2) 一次性任务,同步等结果
echo "具体任务描述,写清楚目标/范围/期望输出" | $S/run.sh .
# 输出是一行 JSON: .result / .is_error / .total_cost_usd / .num_turns
# 本地 task.md 只会追加一行摘要(时间/profile/OK|ERROR + 结果前 200 字),不会抄远端完整内容

# 3) 长任务,起后台进程立即返回
echo "具体任务描述" | $S/start-bg.sh . my-build-task
# 4) 之后随时查进度
$S/status.sh .
```

- `run.sh`/`start-bg.sh` 的 profile 是可选的第二个位置参数:不传就用索引文件夹里记的 profile(如果 `new.sh` 时指定过),再不然用这个 host 的 `default_profile`。再往后的参数是额外的 `--add-dir` 目录。
- 想跳过 profile 覆盖、直接传额外目录,传空字符串占位:`run.sh . "" /some/extra/dir`。

## 安全规则(必须遵守)

1. **永远显式传 `--permission-mode`**,不要依赖远端命令的默认值——有些包装命令(比如路由器类工具)不传时会自己补上"跳过所有权限检查",这两个脚本已经固定传了 `acceptEdits`,别去掉。也别用 `plan` 模式:没人盯着的调用用 `plan` 会要求人工批准计划,永远卡住。
2. **一次性/后台调用一定带 `--permission-prompts none`**(脚本已固定),否则遇到需要确认的操作会挂起等一个不存在的人。
3. **用 `--add-dir` 把访问范围限制在任务目录(+ 明确需要的项目目录)**,不要给根目录或整个 home。
4. **这两个脚本不碰远端 Claude Code 自己的 `--bg`/`agents`/`attach` 这套东西**(原因见下面"已知的坑"),所以也不会跟那台机器上别人/别的会话手起的东西产生冲突。
5. **索引文件夹只放指针,别把远端内容抄过来**——`task.md` 只追加一行摘要,完整结果永远留在远端的 `.result.json`。这样索引文件夹本身是可以随便公开/分享的(不含实际工作内容),也方便同时跟踪很多台机器、很多个任务而不爆炸。
6. prompt 永远走文件传输(先 `cat >` 到远端文件,再在远端读出来),**不要**自己手写 `ssh host "claude -p \"...\""` 这种内联拼引号的命令——prompt 里一旦有引号、反引号、`$`、换行,内联拼接大概率出错或造成注入。

## 已知的坑(实测踩过的,换了机器/工具大概率还会遇到)

- **远端命令可能不在非交互 ssh 的 PATH 里**:很多安装方式(比如装到 `~/.local/bin`)只有登录 shell 的 rc 文件才会加进 PATH。这两个脚本都用 `ssh host bash -ls <<...`(login shell),不要改成普通 `ssh host 'claude ...'`,否则可能报 `command not found`。
- **Claude Code 自带的 `--bg` 不是"后台跑一个任务"的意思**:实测它建的是一个空的交互式会话,等你 `attach` 进去打字才会动;跟在命令后面的 prompt 不会被自动执行,`--bg --resume <id>` 想塞任务进去还会分裂出一份拷贝。所以这两个脚本完全不用 `--bg`,改用 `nohup setsid <bin> -p ... &`,已验证可靠。
- **路由到多个后端模型的包装命令(如 claude-ccr 类工具),不传 `--model` 可能会默认选到一个不稳定的后端**,表现是卡很久(分钟级)才报网关错误,即使健康检查显示正常。每个 profile 一定要把 `--model`(或等价参数)写进 `args`,不要让它"自己选"。
- **某些后端在结果 JSON 前面会混一行非 JSON 的诊断文本**,所以脚本用 `grep '^{"duration_api_ms"'` 只取真正的结果行,不能把整段 stdout 当 JSON 解析。
- **远端进程报业务错误(is_error:true)时,自己的进程退出码也可能是非 0**——这不代表"没跑完",只是代表"跑完了但结果是个错误",`run.sh` 已经处理了这个区别(用 `|| true` 接住,再单独解析 JSON 里的 `is_error` 字段来决定脚本自己的退出码)。

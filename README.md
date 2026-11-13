# delegate-remote

一个 Claude Code Skill:把任务委派给**另一台机器自己的 Claude Code**,而不是在本地假装能操作远程文件。

- 机制:本地的 Claude Code 的 Read/Edit/Grep/Glob 只认本机文件系统,碰不到任何远程主机。这个 skill 不去模拟"远程 Edit",而是把整个任务通过 ssh 整体交给目标机器上已经配置好的 Claude Code 去跑,拿结构化的 JSON 结果回来。
- 约定:每个 `(服务器, 任务)` 配一个本地索引文件夹 `<host>-<task-slug>/`,里面只放指针(去哪台机器、哪个远端目录、用哪个模型/命令),不放实际代码或数据。方便同时追踪很多台机器、很多个任务,而且索引文件夹本身不含敏感/实际内容,可以放心分享。

详细用法、安全规则、已知坑见 [`SKILL.md`](./SKILL.md)。

## 安装

```bash
git clone <本仓库> ~/.claude/skills/delegate-remote
cp ~/.claude/skills/delegate-remote/hosts.example.json ~/.config/delegate-remote/hosts.json
# 编辑 ~/.config/delegate-remote/hosts.json,填你自己的 host/profile(这份文件不会被这个仓库追踪或公开)
```

目标机器(你要委派任务过去的那台)需要:
- 已经能通过 `ssh <host>` 免密登录(这个 skill 不管网络怎么打通——另见 [tailnet-bridge](https://github.com/Johnny-Sun-Git/tailnet-bridge) 之类的工具)。
- 已经装好、配置好 Claude Code(或等价的、接受 Claude Code 风格参数的命令行入口)。

## 文件说明

| 文件 | 作用 |
|---|---|
| `SKILL.md` | 给 Claude 自己看的使用说明(安全规则、怎么选 profile、已知坑) |
| `hosts.example.json` | 配置模板,复制改名后使用,**不提交真实配置** |
| `scripts/new.sh` | 新建一个 `<host>-<task-slug>` 索引文件夹,顺带在远端建好任务目录 |
| `scripts/run.sh` | 一次性任务,同步等结果 |
| `scripts/start-bg.sh` | 长任务,起远端后台进程,立即返回 |
| `scripts/status.sh` | 查后台任务进度/结果 |
| `scripts/lib.sh` / `scripts/_cfg.py` | 内部共用逻辑,不直接调用 |

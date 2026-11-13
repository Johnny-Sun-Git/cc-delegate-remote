---
name: delegate-remote
description: Delegate a single, narrowly-scoped remote-only operation — a file edit, a command/test run — to a Claude Code instance on another machine, when this session's own Read/Edit/Write/Grep/Glob/Bash cannot reach that host's filesystem at all. Reasoning and planning stay in this session; only the step that must physically happen on the other host gets delegated, as one bounded operation at a time, never a whole open-ended task. Use this whenever cwd is (or should be) inside a `<host>/<group>/.../<task>` index-folder tree for that remote work — it gives each node its own local folder whose CLAUDE.md holds nothing but the user's own intent (inherited down the tree, synced to the remote so the delegate sees it too), never probed facts that could go stale. A plain `ssh <host> 'cat/ls/grep ...'` is still the right tool for a quick read-only lookup; don't spin up a remote Claude Code call just to look at a file.
---

# delegate-remote

一个机制:碰到结构性做不到的事(要动另一台机器的文件/命令),把**那一个具体操作**交给对面机器自己的 Claude Code 去做,而不是试图在本地模拟远程文件操作,也不是把整个任务都甩过去让对面自己判断。
一个约定:本地建一棵嵌套的**索引文件夹**树,`<host>/<group>/.../<task>`,深度不限。每一级只放指针和这一级的**用户意图**,不放实际代码或数据,也不放探测到的具体事实——真正的工作永远留在远端,会变的东西不往这里记。

## 操作方式(在这棵树下工作时的默认心态)

一旦你在为某个 `<host>/...` 索引文件夹下的工作,默认按这个来,不用每次重新想:

- **想知道远端现在是什么样,直接 `ssh <host> '...'` 问**(文件在不在、内容是什么、命令输出是什么)。这是只读查询,不用走这个 skill 的委派脚本,也不用把问到的结果记下来——远端会变,这里的文件只记"想要什么",不记"现在是什么"。
- **只有一件事必须落在远端、且小到能一句话说清楚时,才委派**(改远端一处文件、跑一组远端测试并总结)。规划和判断留在本地这边做,委派出去的应该是边界清楚的单步操作,不是"帮我把这个功能做完"这种开放式任务——复杂任务要先在本地拆成几个这样的单步操作,再逐个委派。
- 目标机器**必须已经有自己配置好的 Claude Code**(装了 `claude` 或等价的命令行入口,能认得 `-p`/`--output-format json`/`--permission-mode` 这类参数)。这个 skill 不负责在远端安装或配置 Claude Code 本身。

## 第一次给某台机器/某个任务建索引:怎么做

1. **先探测,不先建文件夹。** 跟用户聊清楚要做什么之后,自己用 `ssh <host> '...'` 去看一眼实际环境(系统、已有的 `CLAUDE.md`/`AGENTS.md`、关键目录、有没有现成的约定)。这一步只是为了帮你和用户理解情况、聊出"到底想要什么",**探测到的具体结果不要写进任何文件**——只是这次对话里的参考。
2. 聊清楚用户的意图之后,跑 `scripts/new.sh` 建索引文件夹(host 单独一级,或 host+一两级任务,不用每次都建到底)。
3. 用 Edit 把刚才聊出来的"意图"写进对应那一级的 `CLAUDE.md`(模板里"用户意图"那一段;上面骨架自带的操作说明部分不用动)。之后这一级(及它往下的所有层级)干活时,都会带着这段意图。

## 索引文件夹树 —— 层级继承怎么做到的

每一级(`<host>`、`<host>/<group>`、`<host>/<group>/<task>`……)只有两个文件,**故意不留任何会越写越多的东西**(没有运行日志,最新结果永远看远端的 `.result.json` 就好,不在本地攒一份):

- **`.delegate.json`**:机器可读,`{host, remote_dir, profile}`。新建深一级时,`remote_dir` 按路径拼接,`profile` 从上一级继承(除非显式覆盖),人不用管这个文件。
- **`CLAUDE.md`**:只放**用户意图**——这台机器/这个任务,用户到底想要什么、有什么边界/禁区。**不放探测到的具体命令/路径/事实**(文件是否存在、系统细节这类会随时间变化的东西),那些该在需要时重新问远端,不该被当成写死的记忆。host 根这一级额外带一段骨架自带的"操作方式"说明(见上面),不是用户意图的一部分,正常不用改。往下每一级只补充"比上一级更具体"的意图,不重复抄。

**关键机制:`CLAUDE.md` 这个文件名不是随便起的。** Claude Code 本身就会沿目录树往上走,把经过的每一级 `CLAUDE.md` 都加载、叠加到上下文里。`run.sh`/`start-bg.sh` 在委派任务前,会把本地这条索引链(从目标那一级到 host 根)上所有的 `CLAUDE.md` 同步到远端对应的路径;远端的 Claude Code 一启动,沿目录树往上走就会自动看到整条链叠加的用户意图——不用自己写继承逻辑,白捡 Claude Code 自带的能力。本地是编写意图的地方(会被版本控制、可以分享),远端只是同步过去的镜像,改了本地重新 `run.sh`/`start-bg.sh` 一次就会同步最新版。

(已实测验证:host 级和 group 级 `CLAUDE.md` 各写一条互不相同的事实,在最深一级跑任务让它回答这两条事实,远端正确同时读到了两条——证明叠加继承真的生效,不只是文件存在。)

## 第一次用:配置

1. 复制 `hosts.example.json` 到 `~/.config/delegate-remote/hosts.json`(这份文件**不要**提交到任何公开仓库,里面是你自己的机器/模型信息)。
2. 按你自己的情况填每个 host:
   - `remote_task_root`:这台机器上,给委派任务树用的一个根目录(比如 `/home/you/tasks`),对应本地索引树的 `<host>` 这一级。
   - `profiles`:这台机器上有哪些可用的"调用方式",每个 profile 是 `{"bin": "命令名", "args": [...]}`,`bin` 必须接受 Claude Code 风格的参数(`-p "<prompt>" --permission-mode X --permission-prompts none --output-format json --add-dir Y`,以及不带 `-p` 时接受位置参数 prompt)。常见情况: `claude` 本身,或者某个路由到别的模型的包装命令(比如 `claude-ccr --model xxx`)。
   - `default_profile`:新建 host 根这一级时用哪个(往下每一级默认继承上一级,不用在这里每层都配)。
3. (可选)想把配置放在别处,设环境变量 `DELEGATE_REMOTE_CONFIG=/path/to/hosts.json`。

## 日常用法

```bash
S=~/.claude/skills/delegate-remote/scripts

# 1) 建一条索引链(任意深度;已存在的上级会被复用,不会覆盖)
$S/new.sh internal torch-sipu symm-mem-fix oom-case
# 建完之后,先去把这条链上每一级新建的 CLAUDE.md 填一下(至少 host 那一级)

# 2) 一次性任务,同步等结果
echo "具体任务描述,写清楚目标/范围/期望输出" | $S/run.sh internal/torch-sipu/symm-mem-fix/oom-case
# 输出是一行 JSON: .result / .is_error / .total_cost_usd / .num_turns
# 本地不会留下任何东西;想回看结果,重新 ssh 查远端的 .result.json 就好

# 3) 长任务,起后台进程立即返回
echo "具体任务描述" | $S/start-bg.sh internal/torch-sipu/symm-mem-fix/oom-case my-build-task
# 4) 之后随时查进度
$S/status.sh internal/torch-sipu/symm-mem-fix/oom-case
```

- `new.sh <host> <seg...> [--profile 名字]`:`--profile` 只作用于本次新建的最深一级。
- `run.sh`/`start-bg.sh` 的 profile 是可选的位置参数:不传就用这个文件夹 `.delegate.json` 里记的 profile(建的时候已经从上一级继承/或显式指定过了)。再往后的参数是额外的 `--add-dir` 目录。
- 想跳过 profile 覆盖、直接传额外目录,传空字符串占位:`run.sh <folder> "" /some/extra/dir`。
- 也可以不建多级,就建一级(`new.sh internal some-task`),跟以前的扁平用法效果一样——层级深度完全看你自己的任务结构需不需要。

## 安全规则(必须遵守)

1. **永远显式传 `--permission-mode`**,不要依赖远端命令的默认值——有些包装命令(比如路由器类工具)不传时会自己补上"跳过所有权限检查",这两个脚本已经固定传了 `acceptEdits`,别去掉。也别用 `plan` 模式:没人盯着的调用用 `plan` 会要求人工批准计划,永远卡住。
2. **一次性/后台调用一定带 `--permission-prompts none`**(脚本已固定),否则遇到需要确认的操作会挂起等一个不存在的人。
3. **用 `--add-dir` 把访问范围限制在任务目录(+ 明确需要的项目目录)**,不要给根目录或整个 home。
4. **这两个脚本不碰远端 Claude Code 自己的 `--bg`/`agents`/`attach` 这套东西**(原因见下面"已知的坑"),所以也不会跟那台机器上别人/别的会话手起的东西产生冲突。
5. **索引文件夹只放指针和用户意图,不留运行日志,也别把探测到的具体事实抄过来**——完整结果永远留在远端的 `.result.json`,本地没有任何会越写越多的文件。`CLAUDE.md` 只是用户想要什么(稳定、由人决定、很少变),不是运行记录,也不是环境探测缓存。
6. prompt 永远走文件传输(先 `cat >` 到远端文件,再在远端读出来),**不要**自己手写 `ssh host "claude -p \"...\""` 这种内联拼引号的命令——prompt 里一旦有引号、反引号、`$`、换行,内联拼接大概率出错或造成注入。
7. `CLAUDE.md` 会被原样同步到远端对应目录,**别在里面写密钥/凭据**——这些文件是要被读、被分享的说明文档,不是秘密存放处。

## 已知的坑(实测踩过的,换了机器/工具大概率还会遇到)

- **远端命令可能不在非交互 ssh 的 PATH 里**:很多安装方式(比如装到 `~/.local/bin`)只有登录 shell 的 rc 文件才会加进 PATH。这两个脚本都用 `ssh host bash -ls <<...`(login shell),不要改成普通 `ssh host 'claude ...'`,否则可能报 `command not found`。
- **Claude Code 自带的 `--bg` 不是"后台跑一个任务"的意思**:实测它建的是一个空的交互式会话,等你 `attach` 进去打字才会动;跟在命令后面的 prompt 不会被自动执行,`--bg --resume <id>` 想塞任务进去还会分裂出一份拷贝。所以这两个脚本完全不用 `--bg`,改用 `nohup setsid <bin> -p ... &`,已验证可靠。
- **路由到多个后端模型的包装命令(如 claude-ccr 类工具),不传 `--model` 可能会默认选到一个不稳定的后端**,表现是卡很久(分钟级)才报网关错误,即使健康检查显示正常。每个 profile 一定要把 `--model`(或等价参数)写进 `args`,不要让它"自己选"。
- **某些后端在结果 JSON 前面会混一行非 JSON 的诊断文本**,所以脚本用 `grep '^{"duration_api_ms"'` 只取真正的结果行,不能把整段 stdout 当 JSON 解析。
- **远端进程报业务错误(is_error:true)时,自己的进程退出码也可能是非 0**——这不代表"没跑完",只是代表"跑完了但结果是个错误",`run.sh` 已经处理了这个区别(用 `|| true` 接住,再单独解析 JSON 里的 `is_error` 字段来决定脚本自己的退出码)。
- **递归/批量删除远端目录前先列一下内容**:这套约定会在远端建出一棵对应的目录树,清理测试数据时很容易手滑删多——养成先 `ls` 再 `rm -rf` 的习惯。
- **委派的 prompt 一旦写成"去把这个功能做完"这种开放式任务,就是用错了**:对面可能是个便宜/弱一些的模型,扔一个大任务过去容易跑偏、也容易为了"完成"而做出你没要的改动。拆成"读这个文件告诉我现状""照着这个思路改这一处""跑这组测试告诉我结果"这种单步操作,一次一个,规划留在本地这边。

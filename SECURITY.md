# 安全与风险说明

> EN: What this kit writes, changes, reads, and can block — and how it fails.
>
> 伴生工具：本页提到的 `guards.ts` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

**一句话结论**：v1 仓库只发**规则书、安装器、脱敏门**，**不发任何门（hook）代码**；装它**不会拦任何命令**。会拦命令的是你自己另装的 hook。参考实现有 7 道门，它们最常见的失败是**静默放行**，不是拦死。

**先读这一句**：**这里没有任何安全边界。** 这套东西是 **guidance，不是 enforcement**。它约束的是流程和写法，不是恶意 agent；真正拦人的是各 harness 自己的 hook 与权限系统。

---

## 1. 范围与威胁模型

### 1.1 这是什么 / 不是什么

- 一套 agent 规则书 + 部署协议。规则书是文本；安装器把文本复制进 harness 配置目录；脱敏门只读、只报告。
- **v1 不发行门（hook）代码**。仓库里的可执行文件只有安装器（`install/install.*` 安装与字节级比对、`install/verify.*` 只读健康检查）和脱敏门（`scripts/check-leaks.sh`）；它们都不拦命令。门的规格在 `protocol/03-gates.md`，实现要你自己写或另取。派发看板与 brief 检查器同样**不随附**，规格在 `protocol/02-dispatch.md`。
- 安装器是可选路径；主路径是 agent 按 `install/INSTALL.md` 手工落文件。

### 1.2 资产与信任边界

| 资产 | 谁可能碰它 | 现有控制 | 残余风险 |
|---|---|---|---|
| 用户 home 下的 harness 配置（`~/.omp/agent`、`~/.codex`、`~/.claude`） | 安装器；agent | 默认不覆盖；冲突退出 2；覆盖前备份；入口块可回滚 | `--force` 覆盖；同秒备份被覆盖；半装时 manifest 未写 |
| 项目文件 / 看板 | agent（按规则书） | 规则 + 可选门；默认无机器门 | 规则不防恶意 agent；门可能没装或没加载 |
| 命令与工具入参 | 可选日志 hook | 只在你装日志 hook 时发生 | 完整命令进用户目录；无轮转 |
| 凭据 / 密钥 | 安装器（复制源文件时）；脱敏门（扫描文本时） | 安装器不解析内容；脱敏门只报告 | `--source` 指错会把凭据复制进规则目录；脱敏门会把命中行打到 stdout |
| agent 进程 | 可选 hook / skill | 无 | hook 是任意代码；skill 是指令注入面 |

### 1.3 不在范围内

- 恶意 agent 故意绕过规则或门；OS / harness 自身漏洞；网络攻击；第三方工具窃取凭据。
- 规则书里每条建议的正确性；不同 harness 的 hook 是否生效（见 `adapters/` 与 `docs/known-gaps.md`）。
- 你从不可信来源拿到的 hook / skill；它们不是本仓库的一部分。

---

## 2. 会写哪些路径

### 2.1 安装器（本仓库唯一会主动写盘的代码）

`<target>` 默认 = `%USERPROFILE%`（Windows）/ `$HOME`（macOS / Linux / Git Bash）。

| harness | 文档落点 | skills 落点（源里有才写） | 入口文件 |
|---|---|---|---|
| omp | `<target>/.omp/agent/AgentRule/` | `<target>/.omp/agent/skills/<name>/` | `<target>/.omp/agent/AGENTS.md` |
| codex | `<target>/.codex/AgentRule/` | `<target>/.codex/skills/<name>/` | `<target>/.codex/AGENTS.md` |
| claude | `<target>/.claude/AgentRule/` | `<target>/.claude/skills/<name>/` | `<target>/.claude/CLAUDE.md` |

- **备份**：覆盖前写到 `<target>/.backup-YYYYMMDD-HHMMSS/<相对路径>`；只备份被覆盖的文件。**备份是原样复制** —— 被覆盖文件里有密钥，备份里也有。
- **状态目录**：`<target>/.agentrule-deploy/<timestamp>/`，写 `manifest.json`（`files[]` / `entries[]` / `backup_root` / `uninstall[]`）和 `apply.log`（逐文件 before/after sha256）。这是卸载/回滚的账本，不是配置；**它含绝对路径和 source/target，不要提交或贴到公开 issue**。
- **建目录**：`AgentRule/`、`skills/<name>/` 按需创建；`--force` 还会创建缺失的 harness home。
- **复制范围（allowlist）**：只复制 `--source/install/scope.txt` 里列出的文件。清单外的文件——本地笔记、未跟踪草稿、`.env`、日志、临时产物——**安装器不打开、不 hash、不复制**。清单缺失 / 为空 / 条目非法 / 条目指向不存在的文件时退 4，不退回「整棵树都装」。清单由 `python scripts/gen-scope.py --write` 生成，`--check` 在 `assemble.sh` 与 CI 里跑，所以清单和发布树不会各走各的。清单里包含 `install/*.ps1`、`scripts/check-leaks.sh`、`SECURITY.md`——它们会被复制，但不会被安装器执行。
- **skills 分支**：源里若有 `skills/<name>/...`，会复制到 `<harness>/skills/<name>/`。skills 是 agent 会读的指令，不是普通文档；只从你信任的源安装。
- **不写**：`config.yml`、`settings.json`、`config.toml`、`mcp.json`、`.claude/settings.json`、`.claude.json`、shell profile、PATH、注册表、服务、计划任务、git config。
- **不联网、不删除、不提权**：安装器里没有 `Invoke-WebRequest` / `curl` / `wget` / `Remove-Item` / `rm -`；写动词只有 `New-Item` / `Copy-Item` / `WriteAllText`（PS）和 `mkdir` / `cp` / `printf`（sh）。

### 2.2 可选门（不在本仓库；装了才写）

参考实现装到 `~/.omp/agent/hooks/`。`~` = `%USERPROFILE%`。这些代码**不在本仓库**；`protocol/03-gates.md` 只写规格，`adapters/omp.md` 讲怎么接。

| 文件 | 读 | 写 | 触发 |
|---|---|---|---|
| `pre/guards.ts` | `hooks/allow/DELETE-ALLOW.txt`；环境变量 `USERPROFILE`、`<BOARD_OWNER_ENV>` | `hooks/log/bash.<epoch-hour>.log`（block / allow 记录） | 每次工具调用 |
| `pre/idle-count.ts` | 工具入参 | `hooks/log/idle-count.log` | 每次 `bash` 调用 |
| `post/log-bash.ts` | 工具入参 | `hooks/log/bash.<epoch-hour>.log`（attempt 含完整命令 ≤4,000 字符；result 只含 `cmd_len`） | 每次 `bash` 调用 / 结果 |
| `post/log-mcp.ts` | 非 builtin 工具入参 | `hooks/log/mcp.<epoch-hour>.log`（入参 JSON ≤1,000 字符） | 每次 MCP / 非 builtin 调用 / 结果 |
| `post/ctx-watch.ts` | `config.yml` 的 `thresholdPercent` | `hooks/log/ctx-watch.log`；消息尾部注入 | 上下文跨阈值 |
| `post/tier-card.ts` | 模型 id、消息数组 | `hooks/log/tier-card.log`；消息尾部注入 | 每个不同用户轮次 |
| `post/recover-pointer.ts` | `NOW.md` / `HANDOFF.md` / `ops/NOW.md` / `ops/HANDOFF.md`、带日期的 `ops/HANDOFF-YYYY-MM-DD*.md`、`<board-root>/boards/registry.json`、`hooks/log/compact-counts.json`、session 文件路径 | `hooks/log/compact-counts.json`（≤200 个 key）、`hooks/log/recover-pointer.log`；压缩时注入 | 会话开始 / 压缩 |
| `allow/DELETE-ALLOW.txt` | 每次递归删除检查时重读 | **写它 = 授权**，不是日志 | 人工维护 |

- **没有轮转**：参考实现实测日志目录 **375 个文件 / 307,722,330 B**；其中 `bash*` **283 个文件 / 301,688,858 B**（282 个小时桶 + 1 个压缩的遗留 `bash.log.gz`）。`bash` attempt **428,311** 条、result **428,192** 条（差 119 条，约 0.03%）。裁剪靠人工，hook 自己从不删。
- 日志里可能有完整命令、cwd、MCP 入参。装日志 hook 前先接受这一点。

### 2.3 规则书引导 agent 写的（不是安装器）

- `<board-root>/board.md`、`<board-root>/boards/*.md`（append-only）、项目文件、规则书自身。
- 这些是工作流约定；安装器**不创建**它们。不跑这套工作流，就不会有这些写入。
- 第 7 道门（`board-write`）只保护看板路径，且只在你自己装了门之后才存在。

---

## 3. 会改哪些文件（已有文件）

| 情况 | 默认行为 | `--force` 行为 |
|---|---|---|
| 入口文件 `AGENTS.md` / `CLAUDE.md` 已存在，且内容不等于目标块（包括空文件） | **冲突，退出 2，一个文件都不写** | 先备份，再把 入口块 追加到末尾 |
| 入口文件里已有 `<!-- BEGIN agentrule:entry v1 -->` | 视为冲突（内容不同） | 用正则替换旧块，**移到文件末尾**；块外内容保留 |
| `AgentRule/` 里同名文件 sha256 相同 | 跳过（`SAME`） | 跳过（`SAME`） |
| `AgentRule/` 里同名文件内容不同 | **冲突，退出 2，一个文件都不写** | 先备份，再覆盖 |
| 目标路径是目录 | 冲突，退出 2 | 仍冲突（不覆盖目录） |

- **全有或全无**：只要有一个冲突，脚本退出 2 且**零写入**。安装器**没有 `--yes`**；只想补缺失文件时，要么手动复制，要么先把冲突文件挪走，要么接受 `--force` 的备份+覆盖。
- **备份可能被同秒覆盖**：备份目录名只到秒；同一秒跑两次，第二次的 `Copy-Item -Force` / `cp` 会覆盖第一次的备份。
- **manifest 在半装时可能缺失**：安装完成时写 `<target>/.agentrule-deploy/<timestamp>/manifest.json` 与 `apply.log`（逐文件 before/after sha256）；复制阶段中断时 manifest 可能还没写，此时按文件清单 + 备份卸载。见 `install/UNINSTALL.md`。
- **`--target` 不是家目录时**：入口块里的路径写死为 `~/...`，不是 `<target>/...`。把试装目录当目标时，入口指针会指向真实家目录，可能指向一个不存在的规则书。
- **不改既有配置键**：`config.yml`、`settings.json`、`config.toml` 里的 model / provider / permissions / approval 都不动。

---

## 4. 会拦哪些命令

### 4.1 本仓库：0 条

安装器不装 hook；`scripts/check-leaks.sh` 只读。**装完这个仓库，你的命令不会被拦。**

### 4.2 可选门：参考实现 7 条

本机参考实现 `~/.omp/agent/hooks/pre/guards.ts` 有 **7 道门**（`grep -c '^    id: "'` = 7）。代码不在仓库里；`protocol/03-gates.md` 只写规格。7 道门都是 **deny-only**：只拒绝，不改工具入参。

| # | id | 拦什么（参考实现的判定） | 放行 / 例外 | 典型误伤 / 边界 |
|---|---|---|---|---|
| 1 | `ai-attribution` | commit / tag / merge / notes，或 `gh pr\|issue create\|comment\|edit` 命令里出现 AI 署名（`Co-Authored-By: Claude/Codex/GPT/...`、`noreply@anthropic.com`、`Generated with ...`、`claude.com/claude-code`、机器人 emoji）；或写 `.git/`、`commit-msg.txt` / `commit-editmsg.txt` / `commit-message.txt` 且内容含署名 | 普通 commit；报告里**引用**署名文本（非 commit 上下文） | 故意把署名写进 commit 的人会被拦；这是规则本身的目的 |
| 2 | `recursive-delete` | 递归 + 强制删除，目标不在 temp：`rm -rf`、`Remove-Item -Recurse -Force`、`rd/rmdir/del /s /q`、Python `shutil.rmtree`、JS `fs.rm(..., {recursive:true})`、.NET `[IO.Directory]::Delete(path, true)`、`find -delete` / `-exec`、`xargs`、嵌套 shell / `$(...)` / 反引号 | `/tmp`、`/var/tmp`、`%TEMP%`、`%TMP%`、`%USERPROFILE%\AppData\Local\Temp`、`...\Roaming\Temp`；或 `DELETE-ALLOW.txt` 里未过期的绝对路径条目 | 任何 temp 外的“合法清理”都会被拦——`DELETE-ALLOW.txt` 就是为一次真实清理加的；只实现 5 道门的精简版 只拦 `/`、`~`、盘根、`*`，`rm -rf ./src` 会**静默放行** |
| 3 | `protected-process` | **整条命令**里同时出现 `Stop-Process` / `taskkill` 和 `chrome` / `chromium` / `codex` / `omp`；然后拦第一个含 kill 的段 | 杀别的进程 | 比“同段”更宽：一条命令里既杀 notepad 又提到 codex，也会被拦；只保护这四个名字 |
| 4 | `powershell-dollar` | `powershell` / `pwsh` 的 `-Command` / `-c` 后面有未转义的 `$`（单引号内除外） | 单引号包住脚本体，或写 `\$` | 合法的 `$env:` / `$_` 必须改写；不是 PowerShell 语法检查器 |
| 5 | `nested-bash` | 命令位置上的裸 `bash -c` / `-lc` / `-xc`，包括 `$(bash -c ...)`、反引号、大写 `BASH`、`sudo/env/time/nohup/xargs/command/exec/eval` 前缀 | 用 Git Bash 全路径，或去掉嵌套 | 这是**Windows PATH** 的怪癖；在 macOS / Linux 上这条规则通常是误伤 |
| 6 | `unexpanded-temp-var` | **写入目标**里出现字面 `%TEMP%` / `%TMP%` / `%TMPDIR%`：重定向目标、`-o/--out/...`、`cp/mv/install/rsync/ffmpeg` 的目标位、`mkdir/touch/tee` 参数、PowerShell `New-Item/Set-Content/Out-File`、Python/JS 写打开 | 读命令、删除命令（归第 2 条）、git pathspec、commit message、`$TEMP` / `$env:TEMP` | 实测唯一一次命中是误伤：`xargs -0 grep -o '%TEMP%'`（当时 1,033 次命中里的 1 次）；精简版更宽，会拦只读 |
| 7 | `board-write` | 截断/覆盖 `<board-root>/board.md` 或 `<board-root>/boards/*.md`（README 除外）：`>`、`tee` 不带 `-a`、`mv`、`cp` 到看板、`dd of=`、`sed -i` / `perl -i`、`git checkout/restore/clean/rm/reset/mv` 碰看板、`Set-Content/Out-File` 不带 `-Append`、Python/JS 写打开 | `>>`、`tee -a`、`Add-Content`、`-Append`、`board.py`；看板 owner 用 `<BOARD_OWNER_ENV>=1` 做快照重写 | 只保护这两个路径，不保护别的日志；owner 环境变量是**故意留的旁路**，不是漏洞，但能被任何能设环境变量的人用 |

**门的加载与禁用（参考实现）：**

- `hooks/pre/*.ts` 由 omp 进程直接 import，**没有 config 开关**；禁用 = 把文件移出 `hooks/pre/`。
- **改文件不重载**：Windows 上 Bun 忽略 loader 的 `?mtime` cache-buster，必须重启 omp。
- 运行时抛异常 → **fail-closed**：`bash` / `python` / `notebook` / `computer` / `write` / `edit` / `task` / `browser` 这些“会改东西”的调用被拦；`read` / `glob` / `grep` 等只读工具照常通过。
- 加载期失败（import / bundle / 语法错）**不走 fail-closed**：handler 根本没注册，等于**没有门**——见 §6.1。
- **7 道里有 3 道是参考实现所在机器的策略**：`protected-process`、`board-write`、完整的 `recursive-delete`。换机器/换工作流要重写；不要照抄。只实现 5 道门的精简版 有意只留 5 道。

---

## 5. 会读哪些文件

### 5.1 安装器

- `--source/install/scope.txt` 列出的文件：逐个 `sha256`，再逐个复制。清单外的文件不打开。
- 目标入口文件：读全文，用于合并 入口块。
- 目标 harness 目录：探测存在性。
- 不读 `config.yml`、`settings.json`、`config.toml`、`mcp.json`；不读 shell profile；不联网。
- **如果 `--source` 指错**：它仍只复制那个目录 `install/scope.txt` 声明的文件，不会扫整棵树。所以指错的风险从「整棵树（含 `.env`、密钥、会话记录）」降到「一个自带清单的树」。反过来说，**任何自带 `install/scope.txt` 的目录都会被当成发布树**——`--source` 仍要指对。

### 5.2 `scripts/check-leaks.sh`

- 递归读 `--root` 下所有文本文件；跳过自身、`.git`、二进制（`grep -I`）。
- 明细每类最多 **3 行**，格式 `文件:行号 [类别]`，**不打行内容** —— 门自己不会再把你正在找的密钥打到终端上。`--verbose` 打印逐规则计数（只有标签和数字）。
- 只报告，不改文件；退出码 **0 = 完整扫描且 `TOTAL: 0`**，**1 = 有命中**，**2 = 扫描失败或不完整**（目录/规则文件缺失、用法错、0 个文本文件、`grep` 出错、没找到 `leaks.local` 且没给 `--no-local`）。
- 规则分两层：**base 12 条**随仓库发布（家目录形状、内网 IP、token 前缀）；**local 29 条**从 `leaks.local` 读（用户名、盘符根、主机名、私有仓名）。**没有 `leaks.local` 时默认退 2**：那 5 类没扫，`TOTAL: 0` 不算数。公开树里显式加 `--no-local` 才接受 base-only 扫描，并在开头打一行 `# NOTE`。
- **`leaks.local` 不应随仓库发行**（它逐字写着被禁字符串，本身就是最完整的泄漏清单）。
- 在不可信的终端/CI 里跑之前，先确认输出不会被公开。

### 5.3 可选门

- 见 §2.2 的“读”列。
- `guards.ts` 每次递归删除检查都重读 `DELETE-ALLOW.txt`；文件不存在/不可读 = 没有条目（默认拒绝）。
- `ctx-watch.ts` 每次启动读一次 `config.yml` 的 `thresholdPercent`。
- `recover-pointer.ts` 读当前 cwd 的看板候选、`<board-root>/boards/registry.json`、`compact-counts.json`、session 文件路径；**不读 session 内容**。
- `tier-card.ts` 读模型 id 和消息数组，用于判断 W/S 档和“每个用户轮次只注入一次”。
- 都不联网、不发遥测。

### 5.4 规则书运行时

- agent 按规则书自己读：`AGENTS.md` / `CLAUDE.md`、`AgentRule/` 页面、项目文件、看板、配置。**没有固定清单**，安装器也管不住。
- 规则书会要求 agent 在动手前读 `protocol/00-floor.md`、`library/floor/incidents.md` 等；这是阅读建议，不是数据收集。

---

## 6. 最坏情况

### 6.1 先直接回答两个问题

**Q1：hooks 写错了会拦死所有命令吗？**

不会“所有命令”，但可能拦死**所有会改东西的调用**：

- 参考实现的 `try/catch` 在**运行时抛异常**时，对 `bash` / `python` / `notebook` / `computer` / `write` / `edit` / `task` / `browser` 返回 block；`read` / `glob` / `grep` 照常。
- 结果：你还能读文件、看日志，但不能跑命令、不能写文件。会话不会完全死，但活干不下去。
- 恢复：把 `hooks/pre/` 整个移走（或只移出问题文件），重启 omp。没有 config 开关。
- **更糟的是加载期失败**：如果 hook 文件 import 失败 / bundle 失败 / 语法错，handler 根本没注册，`try/catch` 也不会执行——这时是**静默放行**，不是拦死。`[INFERENCE]` 该结论由 loader 的 bundling 失败记录（2026-10-03，审计静默死 15 小时）+ 代码结构推出，没有人为制造一次 guards.ts 加载失败来复现。

**Q2：会静默放行吗？**

会，而且这是更常见的失败方向：

- 2026-10-03 的实测记录：给 hook 加一个 import 导致 extension loader 的 bundling 失败，审计**静默死了约 15 小时**，没有任何报错（`post/log-mcp.ts` 头部注释）。
- 2026-10-01 的记录：30 小时内 36 次压缩、0 次 pointer 投递、没有任何错误（`post/recover-pointer.ts` 的 `logEvent` 注释）。后来才加了 `session_start` 日志来区分“没加载”和“事件没触发”。
- `guards.ts` **没有 `session_start` 心跳**：它只在 block / allow 时写日志。一个“加载了但永远不匹配”的门，和一个“根本没加载”的门，在日志上无法区分。
- 所以：**“没有 block 日志”不等于“没有危险操作”**。要证明门活着，必须发一条**应当被拦**的探针命令，看到 `BLOCKED` 才算。

### 6.2 安装器的最坏情况

| 场景 | 会发生什么 | 影响 | 检测 | 恢复 |
|---|---|---|---|---|
| `--target` 指错 home | 全部文件 + 入口块写进错误账号/目录 | 中：白装、污染另一个 home | `--dry-run` 的 `[detect]` / `[dirs]` | 删 `<target>/<harness>/AgentRule`、`skills`，恢复备份 |
| `--force` 覆盖入口 | 旧 入口块 被替换并移到末尾；块外内容保留 | 中：块内自定义内容丢失 | 看备份 + `diff` | 从 `.backup-*` 恢复 |
| `--source` 指错/过大 | 该目录 `install/scope.txt` 声明的文件被复制进 `AgentRule/`（清单外的不复制；没有清单直接退 4） | 中：错树的发布内容进 harness 目录 | `--dry-run` 的 `[scope]` / `[files]` 列表 | 删 `AgentRule/`，轮换可能暴露的凭据 |
| 入口 marker 碰撞 | 用户自己的 `BEGIN/END AgentRule 入口块` 之间的内容被替换 | 中：自定义内容丢失 | 备份 + `diff` | 从备份恢复 |
| 同秒二次安装 | `.backup-<timestamp>` 复用，第二次覆盖第一次备份 | 中：第一次的原始文件没了 | 看备份目录 mtime | 手工保留多份备份 |
| 磁盘满/中断 | 半装：部分文件已写，部分没写 | 中：入口指向不完整规则书 | `verify.ps1` / `verify.sh` 报 FAIL（退出 1） | 重跑；先看 `[summary]` |
| 有冲突但没看退出码 | 退出 2，**零写入**；用户以为装好了 | 中：实际没装 | `echo $?` / `$LASTEXITCODE` | 处理冲突后重跑 |
| 无 manifest | 半装时 manifest 未写：复制阶段中断，`manifest.json` / `apply.log` 还没落盘 | 中：卸载只能靠文件清单 + 备份 | `--verify` 退出 2 | 重跑；按 `AgentRule/` 与源对比手工删 |
| `--target` 试装目录 | 入口块仍写 `~/...`，指向真实家目录 | 低：试装指针指错 | 读入口块 | 手改入口块或不用它 |
| 源里有 `skills/` | 任意 skill 文件复制到 `<harness>/skills/`，agent 可能自动加载 | 高（若源不可信）：指令注入 | `--dry-run` 的 `[files]` | 删 `skills/<name>/` |

### 6.3 门的最坏情况

| 场景 | 会发生什么 | 影响 | 检测 | 恢复 |
|---|---|---|---|---|
| **加载期失败**（import / bundle / 语法错） | handler 未注册，**没有门**，没有报错 | 高：你以为在拦，其实全放行 | 发探针命令，看是否 `BLOCKED`；看 `session_start` 心跳（如果该 hook 有） | 修文件、重启；修不好就移走 |
| **运行时抛异常** | fail-closed：所有 effectful 工具被拦，只读通过 | 中：干不了活，但能读 | `BLOCKED ... [fail-closed]` | 移走 `hooks/pre/`，重启 |
| **规则写宽了**（false positive） | 合法命令被拦；`%TEMP%` 只读、PowerShell `$env:`、temp 外清理都可能中 | 低-中：要改写命令；最坏是工作流停摆 | 看 `hit` 文本 | 改规则 / 加 allowlist / 移走门 |
| **规则写窄了**（false negative） | 危险命令静默通过；精简版只拦灾难性根删除，`rm -rf ./src` 放行 | 高：真删除发生 | 用已知危险样本做红队测试 | 换完整规则；不要用精简版当唯一防线 |
| **`USERPROFILE` 未设** | 看板/temp 路径变成相对路径，第 2、7 道门可能漏判 | 中：门在但匹配不到 | 在目标环境里打印 `$env:USERPROFILE` | 设环境变量；用绝对路径重写规则 |
| **`<BOARD_OWNER_ENV>=1`** | 第 7 道门整体旁路 | 中：任何能设环境变量的人可重写看板 | 看环境变量 / 日志 | 只在受控 shell 里设；用完取消 |
| **`DELETE-ALLOW.txt` 被写** | 写文件 = 授权删除该绝对路径，直到 UTC 到期日 | 高：等于临时删除白名单 | `grep recursive-delete-allow` 日志 | 删条目；改到期日；审计谁写的 |
| **日志无轮转** | 参考实现实测 375 文件 / 307,722,330 B；`bash` 428,311 次 attempt | 中：占磁盘；完整命令进日志 | `du -sb hooks/log` | 人工裁剪，不要自动删 |
| **日志写失败** | 被 `catch` 吞掉，审计静默死亡 | 中：你以为有记录，其实没有 | 看日志 mtime / 发探针 | 修权限/磁盘；不要把日志当唯一证据 |
| **post hook 注入** | 往消息尾部加 user 消息；曾实测 104 次注入 / 47 个 burst / 单 burst 最多 25 次 | 中：上下文变贵、行为被带偏 | `tier-card.log` / `ctx-watch.log` | 移走 post hook；重启 |
| **改文件不重启** | Windows/Bun 不重载；旧规则继续生效 | 中：以为修好了，其实没变 | 看进程启动时间 vs 文件 mtime | 重启 omp |
| **多会话并发** | 多个进程追加同一日志；无锁、无轮转 | 低：行序不保证 | 看日志行 | 接受；或按会话分文件 |
| **harness 升级** | hook API / 加载路径变化，门可能静默停用 | 高：升级后无门 | 升级后发探针 | 重测；锁版本 |

### 6.4 严重度排序

| 失败 | 可能性 | 损失 | 为什么排这里 |
|---|---|---|---|
| 门静默放行（加载失败 / 没装对） | 中-高 | 高 | 你以为有防线，实际没有；没有任何报错 |
| 日志泄露完整命令 | 装了日志就**必然** | 高 | 428,311 条 attempt，完整命令进用户目录 |
| 规则写窄（under-broad） | 中 | 高 | 只拦灾难性根删除，普通递归删除放行 |
| fail-closed 拦死 effectful 调用 | 低-中 | 中 | 能读不能干；可恢复 |
| 安装器指错目标 / 源 | 低-中 | 中-高 | 写错 home；或把凭据复制进规则目录 |
| false positive 误伤 | 高 | 低-中 | 改写命令即可；最坏是工作流停摆 |
| 日志写失败 | 低 | 中 | 审计静默死亡 |

### 6.5 一句话

**最坏不是它拦你，是它不拦，还让你以为在拦。**

---

## 7. 最小权限安装（只想试试的人装什么）

### 7.1 四档，从低到高

| 档 | 装什么 | 写哪里 | 拦什么 | 适合谁 |
|---|---|---|---|---|
| **L0 只读** | 什么都不装；只读 repo | 不写 | 0 | 只想看看、评估 |
| **L1 规则书副本** | 把 `protocol/` + `library/` 复制到临时目录 | 临时目录 | 0 | 想在自己的项目里试读 |
| **L2 规则书装进一套 harness** | `install.ps1` / `install.sh`，只选一套 harness，**不装门** | `<harness>/AgentRule/` + 入口块 | 0 | 想真正用规则、但不要拦截 |
| **L3 加一道门** | 自己写/审 1 道门（建议 `recursive-delete`），不放日志 hook | `hooks/pre/` | 1 道 | 想验证“门”值不值得 |
| **L4 全套参考 hook** | 7 道门 + 5 个 post hook + 日志 | `hooks/` + `hooks/log/` | 7 道 | 接受日志、注入、维护成本 |

**推荐给“只想试试”的人：L1 或 L2，不装门。** 理由：规则书的收益是“读法”，不是“拦截”；门的收益是“兜底”，但它的失败方向（静默放行）和成本（日志、注入、误伤）都比规则书高。

### 7.2 L2 的具体步骤

```powershell
# 1. 先看计划，不写
powershell -NoProfile -ExecutionPolicy Bypass -File install/install.ps1 --harness omp --dry-run

# 2. 确认 [files] / [dirs] / [summary] 里没有意外路径
# 3. 入口文件不存在：直接装。存在（包括空文件）：默认退出 2，零写入
powershell -NoProfile -ExecutionPolicy Bypass -File install/install.ps1 --harness omp

# 4. 如果入口文件已存在：默认会退出 2，零写入。三选一：
#    a) 接受备份 + 入口块：
powershell -NoProfile -ExecutionPolicy Bypass -File install/install.ps1 --harness omp --force
#    b) 只手工复制 AgentRule/，入口自己加一行指针
#    c) 把入口文件挪走，装完再合并回来

# 5. 验收：看 VERDICT: PASS（退出码 0）
powershell -NoProfile -ExecutionPolicy Bypass -File install/verify.ps1 --harness omp --target "$HOME"
```

```bash
# macOS / Linux / Git Bash
bash install/install.sh --harness omp --dry-run
bash install/install.sh --harness omp
bash install/verify.sh --harness omp --target "$HOME"
```

- 只选**一套** harness；不要 `--harness all`。
- 不要 `--force`，除非你接受“备份 + 入口块追加”。
- 不要 `--source` 指向家目录、项目根、含 `.env` 的树。
- 装完看入口文件：入口块 在不在；块外内容有没有被改动。
- **不装门**：报告里写“本机没有机器门”，不要让读者以为有 7 条自动拦截。

### 7.3 L3：只加一道门时的检查清单

1. **自己读一遍门代码**。hook 是跑在 agent 进程里的任意代码，不是配置文件。
2. 只选一道门，建议 `recursive-delete`（损失最大、规则最容易验证）。
3. 放到 `~/.omp/agent/hooks/pre/`，**重启 omp**。
4. **发一条应当被拦的探针**：例如 `rm -rf` 一个 temp 外的测试目录（先建一个空目录），确认返回 `BLOCKED ... [recursive-delete]`。
5. **发一条应当放行的探针**：`echo ok`，确认不被拦。
6. 如果第 4 步没被拦，**不要假设门在工作**：检查文件路径、import、omp 版本、日志。
7. 保留禁用路径：把文件移出 `hooks/pre/`，重启。

### 7.4 不要做

- 不要一次装三套 harness。
- 不要 `--force` 盲跑。
- 不要为了“装进去”而关掉已有的 hook / 权限门。
- 不要用管理员权限跑安装器。
- 不要把 `--source` 指向含凭据的树。
- 不要安装没读过的 hook / skill；它们能读你的文件、改你的提示词。
- 不要把规则书当安全边界；它不防恶意 agent。
- 不要用 `--target` 试装目录后相信入口块（它写死 `~/`）。

### 7.5 卸载

- 删 `<harness>/AgentRule/`。
- 删安装时复制进去的 `<harness>/skills/<name>/`（源里没有 skills 就没有）。
- 入口文件：从 `.backup-*` 恢复，或只删 `<!-- BEGIN agentrule:entry v1 -->` 到 `<!-- END ... -->` 之间的块。
- hook：把 `~/.omp/agent/hooks/pre/*.ts`、`post/*.ts` 移出（没有 config 开关）。
- 日志：`~/.omp/agent/hooks/log/` 不会自动清；确认不再需要审计后再删。
- 安装器写 `<target>/.agentrule-deploy/<timestamp>/manifest.json` 与 `apply.log`；按 `uninstall[]` 卸载。manifest 缺失（半装）时按清单 + 备份。卸载前先 `--verify`，卸载后再跑一次确认 `MISSING`。详见 `install/UNINSTALL.md`。

---

## 8. 这次没证明什么

- **没有在干净 VM / 干净账号里跑过安装器**；结论来自代码阅读 + 现有安装痕迹。
- **`install.sh` 只读了代码，没有在 macOS / Linux 上实跑**；它的冲突/备份逻辑与 `install.ps1` 同构，但未实测。
- **没有人为注入异常来复现 fail-closed**；该行为来自 `guards.ts` / 精简版的 `try/catch` 代码路径。
- **没有复算** `tier-card` 的 104 次注入 / 47 burst / 单 burst 25 次；该数字来自文件头注释（作者实测）。
- **没有复算** 15 小时静默死亡、36 次压缩 / 0 次投递、1,033 次命中 / 1 次误伤；这些来自代码注释里的历史记录。
- **没有审计整本规则书的每一条指令**；本文只覆盖安装器 + 可选 hook 的副作用。
- **没有实测 Codex / Claude Code 的 hook 行为**；两家的门是否存在、是否生效，见 `adapters/` 与 `docs/known-gaps.md`。
- **没有做恶意样本分析**；hook 是任意代码，本文只描述参考实现的已知行为，不保证第三方 hook 安全。

---

## 9. 复现与验收

```bash
# 安装计划（不写）
powershell -NoProfile -ExecutionPolicy Bypass -File install/install.ps1 --harness omp --dry-run
bash install/install.sh --harness omp --dry-run

# 装完健康检查：看 VERDICT: PASS（退出码 0）。逐字节比对另跑 install.ps1 --verify，看 bad 0
powershell -NoProfile -ExecutionPolicy Bypass -File install/verify.ps1 --harness omp --target "$HOME"
bash install/verify.sh --harness omp --target "$HOME"

# 参考实现的门数
grep -c '^    id: "' ~/.omp/agent/hooks/pre/guards.ts    # 7

# 参考实现的日志规模
cd ~/.omp/agent/hooks/log && ls -1 | wc -l               # 375
du -sb .                                                  # 307722330
grep -h '"decision":"block"' bash.*.log | wc -l           # 1043
```

**统计口径**：日志数字是 **2026-11-02** 的参考实现快照；按小时分桶，随时间增长；换机器/换 harness 不保证成立。分母写在每条命令旁边，不跨时点混用。

---

## 10. 三句话

1. **装规则书不会拦任何命令**；它改的是 agent 读什么、怎么写，不是权限。
2. **要拦命令，得自己装门**；门写错的两个方向是“静默放行”和“拦死 effectful 调用”，前者更常见、更危险。
3. **只想试试：L1 只读或 L2 单 harness 规则书，不装门、不装日志、不 `--force`。**

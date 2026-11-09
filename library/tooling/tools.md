<!-- source: AgentRule/工具.md @ 443d8aa1 -->
# 工具
> EN: What is installed and how to use it: session search, the gate runner, briefcheck, browser control, code graph, MCP policy, encoding checks.
<!-- summary: 本机装了哪些工具、怎么用、MCP 与编码检查的政策边界。 -->

> 伴生工具：本页提到的 `<sessq, sessread, gatecheck, run_all_gates.py>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

已装的 skill / MCP / LSP：有用就用，不用先问。你点名的必须对档。

说「能用」前先分清三层：**本机装了** → **这家 harness 注册了** → **这一轮真调得到**。只有第三层是「现在可用」；到第二层就写「已注册，运行态未验证」。跨 harness 不默认共享。

## 速查表

| 要干什么 | 用什么 |
|---|---|
| 查历史 / 读某条会话 | `sessq` 找，`sessread` 读：id、URI、路径都行（这两件工具不在本仓库，见页首「伴生工具」）。细则 `library/tooling/archaeology.md`。禁止整份读 jsonl |
| **跑一遍所有机器门** | `python "~/.omp/extra-hands/CACHE/run_all_gates.py"` —— **一条命令，套数与名字以它自己打印的清单为准**（2026-10-30 实测 24 套；该工具不在本仓库，见页首「伴生工具」）。**别在这里抄清单**——清单抄一次漂一次。**实测成本 real 5m27.6s；绿/红数以当轮输出为准**（2026-10-12 多轮实测 16 绿 / 5 红；更早的 12/6、17/4 已过时）**引用前重跑**——红的是 board state · credential sweep · missing projects · gatecheck · report stamp，外加运行器自己那一行 `ops/board.md rows: 2614 -> 2618 *** LEAKED 4 rows ***`（不是门泄漏，是长跑会话的派发）。任何一项红则退出码非 0，并核验生产看板 `ops/board.md` 零增长。**先跑这个再引用任何「N/N 通过」**（`存在` ≠ `被跑过`）。自检红路径：加 `--selftest`。另有两件按需手动跑：`prune_hook_logs.py`（修剪分桶日志，hook 永不删）、`orphan-state.py`（不进门的按需命令）。⚠ **本命令的账本泄漏检查在并发下不可判读**：报泄漏前先看行时间戳。⚠ **`gatecheck` 已并入上面这条命令（不再手跑）**。 |
| **压缩恢复链 A/B** | `python "~/.omp/extra-hands/CACHE/pointer-ab.py"` —— 比对「带新恢复指针」与「不带」的会话，**压缩后第一轮**的工具调用率 / 提问率 / 引用板率，每项都带分母。**样本不足时故意退出非零且不打印对比**（阈值 20/边）。别把样本悬殊的两边当结果 |
| **查无主状态文件** | `python "~/.omp/extra-hands/CACHE/orphan-state.py"` —— 列出**存在但没有任何板/文档引用它**的状态文件（`pace*` `progress*` `status*` `state*` `inventory*` `cards.jsonl` `NOW.md` …），自动排掉 `.tooling` `archive/` `reports/` `_superseded/` `node_modules` 等档案区。约 6 秒。**它只列候选不判真假**，所以**它是按需手跑的命令，不进门**。实测抓到过整个仓唯一的真实进度文件、29 份文档零引用 |
| **查语料里的凭据（不回显）** | `python "~/.omp/extra-hands/CACHE/credential-sweep.py"` —— 统计 user 消息里密码/API key/host:port/ssh 形态的条数，**只报数量与分布，绝不回显任何值、也不写盘**。为什么重要：`sessions-v2.sqlite` 的 `msgs` 是 **FTS5 虚拟表**且索引列就是正文，`session_index_v2.py` 用 `WHERE msgs MATCH ?` 搜它 ⇒ `sessq` / `session_read` 会原样返回正文。实测 **222 条消息**（grok 173 / omp 39 / codex 2）—— 但**不同凭据值只有 33 个**，其中一个 api_key 单独出现 145 次 ⇒ **轮换的工作量是 33 不是 222（6.7×）**。⚠ **两个数都是真的，别混用**：222 = 暴露面（多少条消息可能泄），33 = 轮换面（要改几个密钥）。只报 222 会把工作量放大近 7 倍，**该门现在是红的，这是实情不是误报** |
| 收尾自检（逐项细看） | `gatecheck [--days N]`（该工具不在本仓库，见页首「伴生工具」）：dispatch 回条失败态 / brief 反斜杠 / hook 命令路径 / 会话卫生 / 超大文件 / 空转痕迹。**有真踩门就退非零**：`gatecheck.py` 的 `counted` 列表（2026-10-15 重钉；自查 `grep -n 'counted = \[' gatecheck.py` → :1183）是 **7 项计入退出码**（receipts · briefs · configs · floors · board · dispatch sync · uncovered copies），另 5 项咨询性（`n_advisory` 写死 5，自查 `grep -n n_counted gatecheck.py` → :1213）。**别把 exit 0 读成「那 5 项也干净」**；计入踩门数 >0 才是红（2026-10-13 W25 实测 7 项全过、exit 0） |
| 派发前查 brief | `briefcheck <brief>`：**9 项**——fence · `# Non-Conflict` 独占写路径 · `DONE WHEN` 完成条件 · 报告落点（认 `report/报告/回执/receipt/artifact/output` 六个段名）· 反斜杠丢失 · `read` 文件读不到 · **`needs`**（`needs_body` 段；自查 `grep -n needs_body briefcheck.py` → :301，2026-10-15 重钉）· **`env` 环境断言**（未进 `# Env-Claims` 段 → 拒；段内缺标注 → warn）· `board: <id>`（**唯一只 warn 不 fail 的一项**）。docstring 与代码同为 9 项（2026-10-13 W25 已修——此前自述只列 7 项） |
| 配置里写路径 | 会过 shell 的地方（hook、statusLine 命令）路径写**正斜杠+引号**：`"~/.omp/agent/hooks/post/recover-pointer.ts"`。POSIX 层会吞掉未引号的反斜杠；`gatecheck` 会点名 |
| 验编码 / 截中文 | **一律用 Python**。Git Bash 的 `cut` 按字节切：CJK 截断产生非法 UTF-8 → 显示层整段**假 mojibake**（文件真身无损；2026-10-16 两次实测，见 `ops/detail-2026-10-16-utf8-audit.md`） |
| 普通学习 | 随意联网。不用先问 |
| 联网 404 分诊 | **先分清是哪一个 404，别一律当联网坏了**（三种完全不同的病）：`/json/version` **404 是 Chrome 153 inspect 模式的预期表现，不是错**（chromedev MCP 照常工作）；`127.0.0.1:9333/...: fetch failed` 是那个 agent Chrome 没在跑，真问题；`401 / Not signed in` 是 auth 掉线，Owner 自己处理。**`web_search` 本身实测正常。**
  **但它走的是工具，不走模型角色** —— 本机目录里**零个 `web/*` 模型**，`modelRoles.web` 原来指的 `web/exa` 是悬空引用，已改掉。**别把「联网能用」和「web 角色能用」混为一谈。** |
| 库文档 | 直读官方文档/仓库（**context7 已根除**——实测零使用；不要为了 API 去 scrape 整站） |
| 网页 | 先搜**摘要**。只有这一页就是答案再打开/scrape |
| 按键 TUI | 一个 PTY 驱动工具。helper 必须 `stdin=DEVNULL`。**要点（2026-10-13 实测）**：① `send-line` **不进 Claude Code**——用 `send-text` + `keys Enter`；② 模态对话逐字 `keys`（不能整段贴）；③ `resize --rows 90` 后再抓屏；④ 全路径调用（不在 PATH）；⑤ 本地检查不烧 API 额度 |
| 操控浏览器 | chrome-devtools，9333。打开、点击、填写、截图自己做。细则 `library/tooling/browser.md`。**pin 1.10.1 + `--workspace` 收窄到 `.owner`+`Temp`+`<project>`**（全开 `~` 是浏览器侧绕过 bash 守卫的读写口；见 `~/.local/bin/agent-chrome-mcp.cmd`） |
| 符号 / 调用链 | codegraph，带 `projectPath`。细则 §代码智能 |
| 只读审计 | 同进程 `verifier` / `reviewer`；不授权改文件 |
| Origin 压缩后接上 | cwd 在 origin 时用仓库里的 skill `origin-recover`。Codex 用户目录那份不全局自动加载 |
| DeepSeek | 不是单独软件。**当前 `modelRoles`（`config.yml`）以现读为准**——`config.yml` 由多个会话同时改，读数只有几分钟保鲜期，引用前重读一遍。**「七通道同值 / 子模型与父一致」不再是不变量**（2026-10-13 授权「主控 GPT6.1 Sol」；**2026-10-14 r43 更新：gpt6.1sol 暂不可用，Owner 说再用才用**，子任务用父代批准的 <provider> 模型——GLM5.3 Flash / DeepSeek V4.1 Flash 都可以；`claim-drift` 的 `modelroles-uniform` 条目已删）。**本机没有 `web` 键**。⚠ **opencode-go 是新换 key 才可用、要钱——一般不要默认用；默认线一律 = <provider>（免费自建）**，opencode-go 只做点名/临时用途 |

### omp 自身（2026-10-12 联网盘点，取证 `ops/research-2026-10-12-deepweb/omp.md`）

- **hooks 子系统正式 legacy**：`--hook` 只是 `--extension` 的别名，HookAPI 的 context 名没有 shim。
  本机 `hooks/pre|post` 照旧工作（扩展机制在跑），但**新集成应写 extensions**。
- **分享前先脱敏**：`omp anonymize` / `/dump anon`（18.9.0 起已有）——pre-share 步骤，零成本。
- 上游 = `can1357/oh-my-pi`（npm `@oh-my-pi/pi-coding-agent`，MIT）；`omp update` 自更新
  （2026-10-12 实测 18.9.0→18.9.1，补丁 sha256 校验）。仓库**无 SECURITY.md、0 公告**（无披露流程）。
- **`bash.gitGuard`**：原生守卫「共享检出上的破坏性 git」——待评估（可能优于正则钩子）。

## 撞门怎么办（真拦照办；误拦 ≠ 绕）

hooks / 门说 no = **这次效果不许达成**。处置：

1. 把**拒绝原文 + 复现命令 + 你本来想做的合法操作**落盘。
2. **真拦**（门判对了）→ 照办；要跑同类效果就用**硬地板写死的放行形态**（如 `"C:/Program Files/Git/bin/bash.exe" -lc`、powershell 用单引号包外层），或交回 Owner——**不许自创等价绕道**（绕道本身是更贵的事故源）。
3. **误拦**（门判错了）→ **单独修门**（先写行为夹具再改门，防回归）；修好前可用等价合法形态，并记进 `CACHE/*.tests.*`。

**外部 API 配额与文件重名（2026-10-12 实测，<lane-a> lane）**：
- **GitHub 未认证 API = 60 次/小时**，批量抓取中途必耗尽（403 + `remaining: 0`）——兜底 = 改走**目录页 HTML 解析**（不耗配额）；批量前先 `curl -s https://api.github.com/rate_limit` 看余量。
- **按 basename 落盘 = 覆盖事故**（`database/schema.rs` 与 `game_log/schema.rs` 同名，先写后覆盖）——凡从多目录取文件，**按全路径重命名**再落盘。

**临时目录边界（2026-10-13 实测）**：门只认 `%TEMP%` 那一个根——**`D:\tmp` 不算 temp**（在里面递归删照样拦）。
要搬走大目录：`robocopy <src> <dst> /MOVE`（清空源）——但**被搬的源目录必须落在 temp 根内**才豁免；
临时报告库用 `.owner/tmp/`（本机约定），`C:\tmp` 只放短命探针。

## git 2.55 的 `cat-file --batch-check` 会静默算错可达体积（2026-11-01 实测）

`git version 2.55.0.windows.3`：`rev-list --objects --all | git cat-file --batch-check`
每行返回 `... missing`，**不再按空格切分 `<oid> <path>`**。于是

```bash
git rev-list --objects --all | git cat-file --batch-check | awk '$1=="blob"'
```

匹配 **0 行** → 可达体积恒为 0 → 每个仓都会被判成「100% 垃圾」。一轮 18 个仓差点全被误判。

**正确做法**：只喂裸 oid（`rev-list --objects --all | awk '{print $1}'`），
并用 `git fsck --unreachable --no-reflogs` 对拍自证——本轮 4/4 完全一致（17/39/9/0）。

**同类陷阱**：`awk` 32 位整数溢出会把字节和算成 `-2147483648`；求和一律用 Python 64 位。

## MCP 成本按会话计；用户级精简 + 项目级按需（2026-10-17 起）

> **本节只对 omp 生效。** `~/.omp/agent/mcp.json` 与 `~/.omp/profiles/*` 是 omp 的用户级文件；claude / codex / grok 不要动它们（硬地板「不许改别家 harness 的活配置」）。

**为什么**：MCP 里的 `stdio` 类型**每个会话各起一个独立进程**（`omp://mcp-runtime-lifecycle.md`）。
全局配 MCP × **N 个会话** = 纯浪费，且随会话数线性增长——而这 N 个会话里只有一两个真需要。
**引用前自己数，而且必须说清口径——下面这几个数不是一回事**：
```
口径四条（**数只以当轮输出为准，别抄本文**；2026-10-30 实测值在括号里）：
  find ~/.omp/agent/sessions -mindepth 1 -maxdepth 1 -type d | wc -l              # cwd 变体目录（46）
  find ~/.omp/agent/sessions -mindepth 2 -maxdepth 2 -name '*.jsonl' | wc -l      # 顶层会话正文（60）
  find ~/.omp/agent/sessions -name '*.jsonl' | wc -l                              # 全部 jsonl（3671）
  python -c "import sqlite3;print(sqlite3.connect(r'~/.omp/extra-hands/CACHE/sessions-v2.sqlite').execute('select count(*) from files').fetchone()[0])"  # 索引行（2158；本机无 sqlite3 CLI）
```
⇒ **引用会话数量必须带口径；不带口径的数字不许写进任何文档。**

**现在的配置**：

| 位置 | 有没有 |
|---|---|
| `~/.omp/agent/mcp.json`（默认档） | `mcpServers` = `{codegraph}`（**1 个**；2026-10-17 起 `chrome-devtools` 移出默认档、按项目启用；`codegraph` 有守卫包装，无索引即零工具 stub），`disabledServers` = `[]` |
| `~/.omp/profiles/<profile>/agent/mcp.json`（<profile> profile） | `mcpServers` = `{chrome-devtools, codegraph, <profile>}`（3 个）——只在 `omp --profile <profile>`（或 `OMP_PROFILE=<profile>`）下起；<project-b> / <profile> 线用这个 |
| 项目级 `<project>\*\.omp\mcp.json` | **按需允许**（2026-10-17 Owner 裁决）：只写该项目需要的 server；必须本地未跟踪、无凭据；当前由各项目按需添加 |
| **外家格式**的项目级文件（`.vscode/mcp.json`、根 `.mcp.json`、`.cursor/mcp.json`） | **存在且会被 omp 导入**——2026-10-13 实测 3 棵树：`<repo>/.vscode/mcp.json`（**2026-10-13 已收窄为 codegraph 单条**，serena/gitnexus 移入 `_removed`，见 `ops/detail-2026-10-13-mcp-fix-round.md`）、`<device-project>/sources/…/.mcp.json`（macOS 路径死配置）、`<project-h>/*/.cursor/mcp.json`（空）。⇒ 外家格式项目级文件仍禁止；omp 原生 `<项目>/.omp/mcp.json` 按需允许（见上表） |

⚠️ **别用 `disabledServers` 来「关掉」全局 MCP —— 那是错的，而且会连带把项目级的也关掉。**
`omp://mcp-config.md` 原文：`disabledServers` 是**最高优先级的拒绝名单，
它把同名 server 从任何来源藏掉**（`enabledServers` **不能**推翻它）。
**正确做法：全局的 `mcpServers` 留空就够了**，空 map 本身就不会定义任何 server，
不需要 denylist 来「关」。

**⚠️ 项目级文件里的 `enabledServers` 不是多余，是无效。**
`omp://mcp-config.md` 把这两个键限定为
「**The active profile's user file** supplies two cross-source overrides」——
它们**只从用户级文件读**。写在 `<项目>/.omp/mcp.json` 里**不生效**，
而且会误导下一个人以为「我已经在项目级开好了」。
（`enabled` 字段本身的语义仍如原文：它只在源条目写着 `enabled: false` 时被 `enabledServers` 强制打开。）

### 你在一个需要 MCP 的项目里，但工具列表里没有 ⇒ 自己配上

（加**新** server 前先拿 Owner 的话——`library/floor/hard-floor.md`；本节步骤 = 你自己的活。）**这是你的活，不是 Owner 的活。** 2026-10-17 Owner 裁决：**项目级 MCP 只允许 `<项目>/.omp/mcp.json`**；根 `.mcp.json` / `.claude/` / `.cursor/` / `.vscode/` 等外家格式仍禁止。项目级文件必须同时满足：

1. 只在项目根的 `.omp/mcp.json`，不写根 `mcp.json` / `.mcp.json`；
2. `git status --porcelain` 里未跟踪：`git check-ignore -v .omp/mcp.json` 能命中，且 `git ls-files --error-unmatch .omp/mcp.json` 失败；
3. 不含凭据：API key / token 用 `${VAR}` 或 `!command`，不写明文；
4. 不写 `enabledServers` / `disabledServers`——这两个键只从用户级读，写在项目级无效。

```bash
# 1. 看用户级已注册了什么（默认只有 codegraph）
cat ~/.omp/agent/mcp.json
# 2. 项目需要 chrome-devtools / 其他 server → 在项目根写 .omp/mcp.json
#    只写这个项目需要的 server；不要复制整份用户级配置
# 3. 确认未跟踪
cd <项目根> && git check-ignore -v .omp/mcp.json && ! git ls-files --error-unmatch .omp/mcp.json
```

**要 <profile>（<project-b> / <profile> 线）：用现成 profile** —— `omp --profile <profile>`（或 `OMP_PROFILE=<profile>`）。该 profile 的用户级文件 = `~/.omp/profiles/<profile>/agent/mcp.json`（chrome-devtools + codegraph + <profile>）；profile 只读自己的用户级文件，看不见默认档的（`omp://mcp-config.md` 的 Profiles 一节）。

**外家格式的既有项目文件不新增、发现即报**（2026-10-13 已知 3 处，见上表）。**用户级默认只留 codegraph**；`chrome-devtools` 按项目 `.omp/mcp.json` 启用；`codegraph` 是否真起由守卫包装按索引存在与否判断。
取证：`ops/research-2026-10-12-deepweb/mcp.md`。

配完用 `/mcp reload` 在**当前会话内**重新发现并重连，**不必重启会话**
（一手依据 `omp://mcp-config.md`；把它当「必须重启」会把运维成本高估一个数量级，
还会诱导「全杀重开」，丢未落盘状态）。
要立刻验证：`/mcp list` 看它从哪个文件来的、`/mcp test <名字>` 试连接。

**别为了「以防万一」往用户级塞 server** —— stdio 是 per-session 进程：codegraph 有守卫包装（无索引即起零工具 stub，代价 = 一会话一个 ~20MB python；2026-10-14 起，此前 exit 0 会报失败横幅），但 <profile> **每会话常驻 2 个 python server**，代价真实（2026-10-13 夜起 `<profile>` 已移出默认档——要它就用 `omp --profile <profile>`；`<profile>-docs` 已删；历史上那两个合计 3 个 python/会话）。

**跨家 MCP 开关表（2026-10-13 实测口径）**：即使**一个 MCP 都不用**，开机后也会付 ~9 个进程 / 215–285MB 的底噪。各家关法不同：

| 家 | 关法 | 备注 |
|---|---|---|
| omp | `--profile <名>`（如 `--profile <profile>` 反向=只开该档） | 配置文件改动需新进程；会话内 `/mcp reload` |
| claude | `claude --strict-mcp-config`（忽略全部 MCP 配置） | claude.ai **账号级**面另算：24 技能 / 7 MCP ≈ 4260 tok/轮，**只能账号侧关**（4 账号连接器 64 工具同此） |
| codex | `codex -c mcp_servers.<名>.enabled=false` | 死注册的 MCP server 待处置（codex 侧） |
| claude hooks | `[compat.claude] hooks=false`（omp 配置） | 会切断 grok 的 hook 源——改前先确认谁在用 |

**MCP 连接是 per-process 的**（2026-10-14 实测）：配置文件只对**新起的 omp 进程**生效；同一进程里新开会话拿到的还是旧集合。已经开着的 TUI 用 `/mcp reload` 重新发现（`omp://mcp-config.md`），或重开进程。

## 代码智能（CodeGraph / LSP / 检索上限）

`~\.mcp-guard\guard.py` 已不存在，也从未被任何 harness 注册过——不要复活它。要按项目起 MCP：只写 `<项目>/.omp/mcp.json`（未跟踪、无凭据；不写 `enabledServers` / `disabledServers`）；用户级默认保持 `codegraph` 一个。细则 §MCP。

家目录不要 `codegraph init`。符号和调用链用 CodeGraph，调用时带 `projectPath`；没有 `.codegraph/` 就用普通搜索。GitNexus 和 Serena 已从全局 MCP 拆掉，不要再启动；<repo> 仓库的 `AGENTS.md` 若还写着 GitNexus，工具不在就按那一页的有界搜索，不要为了这段把服务器装回全局。

**检索要硬上限**：大 repo 里先 `rg -l` 列文件、`-m N` 限每文件命中、按需截断——**别让一条命令的输出进会话**。单条工具输出超过 ~100KB 就是事故（实测一条 `rg` 出过 1MB，同一条结果存了两份 2.3MB，把会话撑成 80MB）。`Select-Object -First 100` 这种管道限流不保险，要在源头限。

| 工具 | 干什么 | 哪里用 |
|---|---|---|
| CodeGraph | 结构、调用链。调用带 `projectPath` | 有索引的任何项目 |
| Beads | 本地队列。ready → 认领 → 真跑过才 close。不要提交 `.beads` | origin |

**LSP（已在 PATH）**：Go `gopls` · Python `pyright` · TS/JS `typescript-language-server` · Rust `rust-analyzer`。Claude 已开对应官方插件；omp 按 PATH 自动找。没点名 Java 活不要装 jdtls。

机子笔记：`~\.omp\extra-hands\`（INTEL / CACHE / THINK）。谁的文件谁写。

> **计数纪律**：任何改动若增加了门的数量、文件的数量、工具的数量，改完立刻 `grep -rn '<那个数>'` 全树找一遍。
> 防漂移登记在 `claim-drift` 的 `CACHE/claim-drift-registry.json`（漂移即退出码 1）。
> 计数以代码为准：套件数逐条读 `run_all_gates.py` 的元组，`briefcheck` 项数读 `briefcheck.py`。

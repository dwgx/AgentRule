# 已知缺口 / Known gaps

> EN: Which promises this release cannot keep, and how to tell when you have hit one.

这份清单不列装配缺陷（缺文件、编码错、路径没改），只列**这套东西在设计上还解决不了什么**。按问题类型分节，每节四件事：缺口、代价、现在的缓解、真解决需要什么；末行是一条判据，能自己跑。

三条贯穿全篇的事实，先记住：

1. **仓库只发规则文本，不发执行层。** `scripts/` 里没有会拦命令的东西：只有脱敏门 `check-leaks.sh`、上下文预算 `budget.py`、协议账本校验 `check-protocol.py`。
2. **门是可选参考实现，不在仓库里。** 7 道门的代码在用户 home 的 hooks 目录，仓库只给判据和伪码（[protocol/03-gates.md](../protocol/03-gates.md)）。
3. **agent 和用户是同一个 OS 账号。** 任何「拦住」的说法都要先过这一条（见 §6）。

用法：按节末判据自查；修好一条要有回归测试才从本文件删掉；**不要把这份清单当防线**，它描述的是缺陷。

---

## 1 · 伴生工具不在仓库里

**缺口**：正文反复引用的 11 个名字——`board.py`、`briefcheck.py`、`guards.ts`、`run_all_gates.py`、`gatecheck.py`、`omp_dispatch.py`、`hook_probe.py`、`sessq` / `sessread`、`append_session.py` / `merge_sessions.py`——都不随仓库发行。发布决定是只发脱敏门：发一个半脱敏的工具比不发更糟，读者会以为它对自己的项目也适用。

**代价**：在 22 篇原稿上量过，**277 / 1,602 非空行（17.3%）依赖陌生人拿不到的东西**，其中 201 行（12.5%）就是这类私有工具名；`board.py` 出现 32 行、`briefcheck` 26 行、`guards.ts` 15 行。读者按字面执行会得到 `command not found`；更糟的是，他会以为门在跑。硬地板里带门的那几条，在陌生机器上全部没有执行层——**这套规则的可执行部分是 0**。

**现在的缓解**：页级「伴生工具」banner 列出本页依赖哪些不随附的名字；行内标「参考实现，不在本仓库」；[protocol/03-gates.md](../protocol/03-gates.md) 只给判据和最小伪码，不给实现；派发协议用文字描述状态机，不要求读者跑 `board.py`。

**要真解决需要什么**：两条路，二选一。**(a)** 发行一份可离线 fixture 喂 stdin 测的守卫本体 + 各家薄壳，并承担 harness 版本漂移的维护成本；**(b)** 把每处依赖改写成自包含命令或纯判据，并在每页顶部声明「本页命令不可直接运行」。**不能**用「把规则拼成一个 `AGENTS.md`」来绕过——Codex 在 32,768 B 处静默截断（见 §5）。

**怎么知道自己踩到了**：`ls scripts/` 里没有 `board.py` / `briefcheck.py`，而 `grep -rl --include=*.md 'board.py' . | wc -l` 非 0；或者照文档跑一条命令，得到 `command not found` / `No such file`。

---

## 2 · MCP 写操作没有门

**缺口**：MCP 工具名是 `mcp__<server>_<tool>`，不在 7 道门任何 `applies()` 认的三个集合里（`COMMAND_TOOLS` / `CONTENT_TOOLS` / `EFFECTFUL_TOOLS` 都不含）。`post/log-mcp.ts` 只写审计，没有 `return { block: … }` 分支。**结论：0 道门**，这是读代码得出的，不是猜的。

**代价**：较早的语料快照是 **1,565 次调用 / 750 个写形状**；用 87 个现存日志重算得 **1,424 次 / 758 个写形状**（15 个写工具，`evaluate_script` 462、`navigate_page` 175、`click` 43、`new_page` 39、`upload_file` 10……）。两个数的分母不同，结论相同。这些动作在浏览器里跑任意 JS、点按钮、上传文件、装扩展，没有一次被拦。另有 `write` + `xd://mcp__…` 这种调用形状（会话语料 165 条），历史判据同样看不到。

**现在的缓解**：设计已经写完但**未实现**——带到期日的授权文件（一行 = `<项目根> | <server> | <YYYY-MM-DD> | <理由>`）、token 分类器（45 个实测工具名上 0 假阴性 / 0 假阳性）、65 个 case 的测试规格。硬地板里「MCP 按项目、要 Owner 点名」目前是纸面规则。

**要真解决需要什么**：实现 `mcp-write` 门，并**先修 fail-closed**——现有 `catch` 只在 `tool in EFFECTFUL_TOOLS` 时 block，而 MCP 名不在该集合，新门一旦抛异常，写动作会静默放行。门要覆盖两种形状（直接 `mcp__` 与 `write` + `xd://mcp__`）；第三种形状（bash 里直连 CDP / stdio / HTTP）这道门打不到，需要内容门或网络层。最后要说清它买到的是**可见 + 停顿 + 留痕**，不是拦截（见 §6）。

**怎么知道自己踩到了**：`grep -c 'mcp__' ~/.omp/agent/hooks/pre/guards.ts` 输出 `0`，而日志里 `mcp__` 调用数 > 0、`grep -h '"rule":"mcp-write"' <log-dir>/*.log | wc -l` 输出 `0`——门从没存在过。

---

## 3 · 符号链接洞：temp 里的 junction 能指向任意位置

**缺口**：删除判定 `tempDeleteTarget` 是**纯字符串函数**：只做 `\`→`/`、小写、`posix.normalize`，从不 `lstat` / `realpath`。temp 下的 junction（Windows 重解析点）或符号链接指向任意目录时，`rm -rf <temp>/<link>/x` 仍然判「在 temp 内」。

**代价**：实测过一次，不是推演：在 temp 里建 junction 指向 temp 外，目标目录放 marker，门对 `rm -rf <temp>/<link>/x` 返回 **ALLOW**；真跑后 marker 变成 `GONE`，目标目录被删空。也就是说，任何经过这种 junction 的「temp 清理」都会删到 temp 外。给 `recursive-delete` 加 cd 追踪会把入口从绝对路径扩到相对路径（`cd <link> && rm -rf x`），所以那项改动被判定不做——但洞本身不因此消失。

**现在的缓解**：**没有**。字符串判定是当前设计的一部分（纯函数、离线可测）；`DELETE-ALLOW.txt` 只管「允许删哪里」，不管「链接指向哪里」；文档也没有提示这个洞。

**要真解决需要什么**：在判定阶段对每个目标做 `lstat`，遇到 reparse point 就拒绝，或解析后重判。但检查与删除之间有 **TOCTOU 窗口**：光加 `realpathSync` 不等于修好，链接可以在检查之后、删除之前被换掉。要么用句柄式删除（打开时带 `FILE_FLAG_OPEN_REPARSE_POINT`，拒绝跟随重解析点），要么先把目标 rename 到隔离区再删。代价是引入 I/O、破坏「纯函数离线可测」，需要单独的 fixture。

**怎么知道自己踩到了**：

```powershell
# 只在 temp 与 home 下建自己的夹具，不碰别人的目录
$v = Join-Path $HOME "gap-victim"; New-Item -ItemType Directory -Force "$v\x" | Out-Null
Set-Content "$v\x\marker.txt" "x"
New-Item -ItemType Junction -Path "$env:TEMP\gap-link" -Target $v | Out-Null
```

然后让 agent 执行 `rm -rf "$TEMP/gap-link/x"`。`marker.txt` 消失、而 hooks 日志里没有 `recursive-delete` 的 block 行 = 命中。

---

## 4 · `ast_edit` 完全在门外

**缺口**：`ast_edit` 在 `guards.ts` 里一次都没出现，直接调用时不在任何 `applies()` 集合里。经 `write` + `xd://ast_edit` 调用时门会跑，但 7 道谓词只认 shell 命令、文件路径、commit message——**没有一道解析 AST 操作**（删函数、改签名、批量重命名、跨文件 codemod）。

**代价**：一个能结构性改任意源文件的工具，删除和重命名不受 `recursive-delete` 约束；改看板内容不受 `board-write` 约束（路径是 `xd://ast_edit`，不是看板路径）；署名检查也看不到。更一般地，`catch` 的 fail-closed 只对 `EFFECTFUL_TOOLS` 生效，**任何新工具默认落在门外**——加工具时没人会记得同时改门。这不是 `ast_edit` 一个工具的问题，是工具清单手写、门默认放行的设计问题。

**现在的缓解**：无。会话语料里至少出现过 1 次直接调用 `ast_edit`；门的三个集合是手写的，没有「未知工具」分支。

**要真解决需要什么**：把 `ast_edit` 加进 `CONTENT_TOOLS`，并解析其 args 的目标路径；把「未知工具」改成 **fail-closed**——任何不在只读白名单里的工具，判据抛异常就 block，而不是静默通过；让工具注册表与门共用一张表，新工具默认受检。AST 操作还需要与文本编辑等价的判据（改哪些文件、删哪些节点、是否碰看板）。

**怎么知道自己踩到了**：`grep -c 'ast_edit' ~/.omp/agent/hooks/pre/guards.ts` 输出 `0`；用 `ast_edit` 删掉一个函数后，日志里没有任何对应 rule 行（没有 block，也没有 allow 记录）。

---

## 5 · 「文件存在」不等于「模型看到了」

**缺口**：harness 读规则文件有自己的上限和发现规则，仓库只能保证磁盘上的字节对，保证不了「进了模型上下文」。Codex 的 `project_doc_max_bytes` 默认 **32,768**，超出**静默截断**，任何地方都不提示。

**代价**：实测一份 40,000 B 的 `AGENTS.md` 只进去 32,768 B，尾部 marker 直接消失。安装验收按磁盘字节 PASS，模型只看到前半截——而尾部常常正是最关键的门和禁令。同类机制还有：`AGENTS.override.md` 顶替、只加载 git root→cwd 这一条链、Claude Code 只在没有 `CLAUDE.md` 时读 `AGENTS.md`。每一种都会让「文件在 = 规则生效」变成假绿。

**现在的缓解**：[adapters/codex.md](../adapters/codex.md) 给出 `project_doc_max_bytes = 65536`；验收要求「独特尾句在 prompt 里出现一次」，不是 `wc -c`；[adapters/matrix.md](../adapters/matrix.md) 给了三种组合的实测（全局 + 项目 / 只有全局 / 只有项目），并说明分隔符只在两份都装时出现。

**要真解决需要什么**：harness 暴露「实际注入的字节数 / 哈希」；或安装器把规则拆成每个都小于上限的多文件 + 索引，并在验收里比对**注入内容**而不是磁盘内容。文档层只能提示，不能强制——这是 harness 的加载策略，不是仓库能改的。

**怎么知道自己踩到了**：在 `AGENTS.md` 末尾写一个唯一 marker，开新会话让模型复述。marker 不出现、而 `wc -c AGENTS.md` > 32,768 = 命中。Codex 上再补一条：`grep project_doc_max_bytes ~/.codex/config.toml` 没有这一行就是默认值。

---

## 6 · 门拦不住「同一用户能自己改授权文件」

**缺口**：agent 和用户是同一个 OS 账号。授权文件（现有 `DELETE-ALLOW.txt`，以及设计中的 `MCP-ALLOW.txt`）、`.omp/mcp.json`、环境变量、`guards.ts` 本身，全在 agent 可写范围。**任何声称「拦住」的设计在这台机器上都是假的。**

**代价**：agent 可以给自己追加一行有效授权、把到期日写到很远、设 `<BOARD_OWNER_ENV>=1` 打开看板旁路、或者直接改 `guards.ts` 删门。事后审计只看到「有一行授权」，看不到「谁写的、是不是自批」。把它当安全边界，半年后就会有人拿它当「已经安全了」的证据。

**现在的缓解**：现有 `DELETE-ALLOW.txt` 有 TTL、必填理由、单文件人类可读、每次调用重读；MCP 版设计沿用同一骨架（**未实现**）。设计里还有两条补丁：对 allow 文件的写记一条 `kind:"grant-write"`（只记不拦），断电开关极性反转（只能关不能开）——同样未实现。这套机制的设计意图是买三件事：**可见**（每次放行/拦截都有审计行）、**停顿**（写动作前需要一行带理由的记录）、**可审**（事后能回答「什么时候、为什么被允许」）。在 `DELETE-ALLOW.txt` 上，可见与可审已经成立；MCP 侧要等门实现才谈得上。三件都买不到「拦住」。

**要真解决需要什么**：权限分离——hook 以另一个账号或服务运行，授权文件 ACL 只读，harness 配置只读挂载；或 append-only 远端审计（本机改不掉）；或用户私钥签名授权（agent 拿不到私钥）。这是一个文档仓库给不了的东西，只能把边界说穿。

**怎么知道自己踩到了**：用 agent 自己的 shell 往 allow 文件追加一行有效授权，重跑一个本该被拦的动作。通过、且日志里只有 allow 行没有 `grant-write` 行 = 命中。或者 `ls -l` 看 `guards.ts` 与 allow 文件的 owner 是不是就是 agent 跑的那个账号。

---

## 7 · 配置存在不等于门在跑

**缺口**：配置文件在，门不一定在跑。Codex 的 `hooks.json` 在没有 `[hooks.state.'<abs path>:<event>:0:0']` + `trusted_hash` 之前**完全不执行，也没有任何报错**；旧版 Codex 没有 `hooks` feature，[protocol/03-gates.md](../protocol/03-gates.md) 里的每道门都退化成**书面规则**；omp 的 hook 在加载期失败（import / bundle / 语法错）时 handler 根本没注册，**不走 fail-closed**。

**代价**：`ls` 看着一切正常、`hooks = true` 也在、验收 PASS，实际 0 道门；事故后才发现。旧版 Codex 上读者会以为规则有强制力，其实只是「门交给模型自己遵守」。这是最容易误判成「Codex 不支持 hooks」的地方。

**现在的缓解**：[adapters/codex.md](../adapters/codex.md) 要求先 `codex features list | grep '^hooks'`，再 `grep -n "hooks.state" "$CODEX_HOME/config.toml"`，并跑一条应被拦的命令看日志；[adapters/README.md](../adapters/README.md) 的验收表要求「`trusted_hash` 在 **且** 日志多一行」；[hard-floor.md](../library/floor/hard-floor.md) 明说「配置存在不是兜底证据」，codex 的真实拦截保持 `[UNVERIFIED]`。

**要真解决需要什么**：harness 提供 `hook status` / 启动日志 / 加载失败即报错；安装器在装完后主动跑一条 canary 命令并检查 block 日志；验收判据从「文件或键存在」改成「行为可观测」。在这之前，任何「装好了」的结论都必须附一条行为探针的输出。

**怎么知道自己踩到了**：跑一条本该被拦的命令（例如对非 temp 路径做递归强删），日志没有新的 block 行，而 `hooks.json` 在、`hooks = true` 也在 = 命中。

---

## 8 · 三家 harness 都没有端到端验收

**缺口**：omp / Codex / Claude Code 三家，都没有做过「装 → 开新会话 → 行为改变 → 卸载」的端到端验收。已经证明的只有：规则进了 prompt、文件按清单到位。**全部 `[UNVERIFIED]`。**

**代价**：读者把验收的 `PASS` 当成「生效」，实际它只证明文件字节对。卸载路径也只做了文件级回滚，没有证明门真的停了。[case-studies.md](case-studies.md) 记的是本机事故，不是陌生人照做后发生了什么。

**现在的缓解**：每篇适配卡给一条行为探针 + 一条回滚命令；`install/verify.*` 自己声明「只证明文件装对，不证明 agent 以后会守规矩」；[UNINSTALL.md](../install/UNINSTALL.md) 给了逐 harness 的关门步骤。

**要真解决需要什么**：定义可判的端到端判据——新会话里模型对一条禁令的反应、一条门命中日志、卸载后同一条命令不再被拦——三家各跑一遍，记录 harness 版本与日期，写成可复跑的脚本而不是叙述。判据要能红：只跑「应该通过」的用例不算验收。

**怎么知道自己踩到了**：装完开一个新会话，问模型「你的规则里第 N 条是什么」。答不出或答错，而 `verify` 显示 PASS = 命中。

---

## 9 · 两套验收器容易混

**缺口**：仓库里有两个都叫「验收」的东西，判据不同：

|命令|查什么|输出|退出码|
|---|---|---|---|
|`install.ps1 --verify` / `install.sh --verify`|**逐文件 sha256**（字节级）|`[summary] ok N  bad N`|`bad > 0` 即非 0|
|`verify.ps1` / `verify.sh`|**健康检查**：文件在不在、非空、入口块、hooks 语法、总量 ±10%|`[summary] PASS/FAIL/SKIP/N/A` + `VERDICT:`|0 / 1 / 2|

**代价**：只跑一个就以为验完了。`verify.*` 通过不代表字节一致（它允许 ±10% 漂移）；`install.* --verify` 通过不代表能加载（它不查语法）。

**判据**：两个都跑。`VERDICT: PASS` **且** `bad 0` 才算装对。

**怎么知道自己踩到了**：只跑了一个，然后对用户说「验过了」。

---

## 10 · Windows PowerShell 5.1 无法解析安装脚本

**缺口**：`install.ps1` 若以 UTF-8 **无 BOM** 保存且含中文单引号字符串，PS 5.1 在非 UTF-8 代码页下会把它们解码成非法 token，脚本整体不可解析。脚本头声明 `#requires -Version 5.1`，所以用户会真的用 5.1 跑。

**代价**：按文档装，第一步就 `ParserError`。PowerShell 7 能解析，所以「我这儿能跑」不构成反证——文档给的是 `powershell`，不是 `pwsh`。

**现在的缓解**：仓库里的 `install.ps1` / `verify.ps1` 已带 UTF-8 BOM（实测文件头 `ef bb bf`）。**改这两个文件时不要保存成无 BOM。**

**判据**：

```bash
head -c3 install/install.ps1 | od -An -tx1     # 必须是 ef bb bf
```

---

## 11 · 脱敏门默认不查本机身份

**缺口**：`scripts/check-leaks.sh` 随仓库发布时只带 **12 条通用规则**（家目录形状、内网 IP、token 前缀）。用户名、`D:` 盘项目路径、`F:` 盘私密目录、内部仓库名属于**本机身份**，规则不随仓库走。

**代价**：没有 `--local` 也没有 `leaks.local` 时脚本**退 2**，不产出 `TOTAL` —— 不完整扫描不给 PASS。（旧版是打一行 `# WARN` 后照常给 `TOTAL: 0`，被当成通过。）

**判据**：

```bash
bash scripts/check-leaks.sh --root .                     # 没有 leaks.local -> rc 2，不给 TOTAL
bash scripts/check-leaks.sh --root . --no-local          # 12 条，5 类没扫，开头 # NOTE，rc 0/1
bash scripts/check-leaks.sh --root . --local <本机规则>  # 41 条（base 12 + local 29）
```

自己写一份 `leaks.local` 放仓库根，逐字列出要禁的字符串。**它不能进仓库** —— 它本身就是最完整的泄漏清单。

**怎么知道自己踩到了**：退出码是 2，或 `# rules` 那行写的是 12 而不是 41。

---

## 12 · 问卷与安装器能力不一致

**缺口**：`install/ASK.md` 会问「开不开 hooks」。当前安装器**不做这件事**：它只写一个入口块、复制规则目录，没有任何写 hooks 的代码。

**代价**：用户答「开」时，如果报告写「已按选择安装」，那是假陈述。

**判据**：

```bash
grep -n "hook" install/install.ps1
```

只出现在提示文本里，就是命中。答「开」时报告必须写「未实现」。

---

## 13 · 安装器不校验源目录（2026-11-05 已关闭）

**原缺口**：`--source` 接受任意目录，递归复制全部文件，只排除 `.git`、`node_modules`、`.backup`。把工作区（含探针、日志、临时产物）传进去，它们会被复制进用户的规则目录。

**现在**：复制范围由 `install/scope.txt` 决定，清单外的文件**不打开、不 hash、不复制**；清单缺失 / 为空 / 条目非法 / 条目指向不存在的文件时退 **4**，一个文件都不写。回归在 `gates/scope_test.py`（造一棵含私人文件的源树，两个安装器各跑一遍，逐文件比对目标与清单）。

**残留风险**：任何自带 `install/scope.txt` 的目录都会被当成发布树 —— `--source` 仍要指对；清单本身写错了，安装器照装（清单是声明，不是审查）。

**判据**：`python gates/scope_test.py` → `VERDICT: PASS`；`python scripts/gen-scope.py --check` → `一致=True`。

---

## 14 · 怎么复现这份清单

1. 把发布树复制到一个空目录（冻结，记 `sha256sum`）。
2. 按 `install/BOOTSTRAP.md` 的字面顺序执行，记录每条命令的退出码与原样输出。
3. 每条缺口按它自己的「判据」跑一遍；**判据要能红**——只跑「应该通过」的用例不算验收。
4. 对比 `sha256sum`，确认复现过程没改动发布树。

## 15 · 这份清单不保证什么

- 不保证列全。列的是**已知**缺口，不是**全部**缺口。
- 不保证每条都实测过。标了判据的可以自己跑；没标的是从设计推的。
- 不保证修法可行。每节的「要真解决需要什么」是方向，不是方案。

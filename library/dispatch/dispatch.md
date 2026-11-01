<!-- source: AgentRule/派发.md @ e10204d8 -->
# 派发
> EN: How to dispatch: reserve a write scope, write the brief, pass briefcheck, hand off, then close with proof — plus fan-out and receipt rules.
<!-- summary: 一次派活怎么占坑、写 brief、过检查、收工带证据，以及扇出与回执。 -->

> 伴生工具：本页提到的 `<sessq, sessread, omp_dispatch.py, gatecheck, run_all_gates.py, guards.ts>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

> **摘要（5 行）**：① 派发链：切 scope → `board.py open`（四参必填）→ 写 brief → `briefcheck` → 派 → `close --verify`。
> ② 工人模板 + 三段纪律：`# Non-Conflict`、`# Report` 落点、回执在父代（exit 0 且产物真在才算）。
> ③ 多路派发：任务图/前沿、并发与收齐、回执逐个核 → 见 §多路派发。
> ④ 恢复 / 旧会话 / 回执 → 见本节尾与 `library/recovery/recovery.md`。

Claude / Codex / omp **都会派、都会接**。
同进程用各家自己的 subagents / IRC（Codex 不要改）。**换一家或换窗口** = 跨进程，入口是 `omp_dispatch.py`（见下）。细则 §协作。
**跨进程派发 = `omp_dispatch.py`（2026-10-31 复核在位；该工具不在本仓库，见页首「伴生工具」）**：`~/.omp/agent/skills/origin-dispatch/scripts/omp_dispatch.py`，子命令 `run` / `resume` / `status`，一 job 一冻结 brief，产物 `ops/jobs/<id>/receipt.json` + `last.md`。旧的 `scripts\dispatch.ps1` 已于 2026-10-17 删除（`cross-dispatch` 空目录归档在 `~/.owner/ops/archive/skill-corpus-20261027`；`~\.local\bin\dispatch.cmd` 已改名 `.disabled-20261027`），**不得执行、不得复活、不要另造 broker**。本文中所有 `dispatch.ps1` / `-Backend` / `-Resume` 例子只是历史契约。
`-Backend claude|codex|grok|omp` 是已删除入口的历史参数（不可执行）。（grok 独立：不作 peer、不宣传，仅 Owner 点名时用）

只有这些时候才能派：

1. 你说派发 / dispatch
2. 当前项目 `AGENTS.md` 要求第二套 CLI
3. 这条活你已经说过「随便派发」
4. 同 harness 内：任务有 ≥2 个互不重叠切片（Owner 2026-10-17 常驻授权；跨 harness 仍按 1-3）

急：先报后端、范围、超时；**测试期不等回话**（`library/floor/hard-floor.md`：一律不问），进正式期或 Owner 已给话时才等一个字。

**「多 subagents」≠「跨 harness 派发」**（Owner 裁定：「没有说明要 dispatch 别的 harness 就别 dispatch」）：没说明时，「多 subagents」= **同 harness 内建多开**（omp 用 `task`，Codex 用原生 subagents）；跨 harness（claude/codex/grok/opencode）**必须被明确说明**——缺省取最窄解释。

**Resume**：同一条活、同一范围、原许可还在、线程没被别人占着，才不用再问。不能靠旧许可扩范围、加费用、抢写手。

## 协作（子代理 / IRC / Resume）

不要限制个数。要限制的是：空转、没名字、把有记忆的人丢掉再开一个空白的。

**同 harness 自主派发（Owner 2026-10-17）**：任务有 ≥2 个互不重叠切片时直接开本家 subagents，不再逐次问；跨家或另一个窗口走 `omp_dispatch.py`（`run` / `resume` / `status`），需 Owner 点名，不要执行旧 `dispatch.ps1`。

| 情况 | 用什么 |
|---|---|
| 同一家、同一个窗口里并行/跟进 | **这家自己的 subagents + 通讯**（下面分家写） |
| 换一家 CLI，或另一个窗口 | `omp_dispatch.py`（`run` / `resume` / `status`）；不执行旧 `dispatch.ps1`；同进程用 `task` + `agent://` |

说开了会话或子代理，回复里要有 session id。没有 id 就是没开。

**omp**：`task` 起子代理，必须 `name`（CamelCase）= IRC 地址 = `history://Name` = `agent://Name`。本 harness 没有 `hub` 工具——旧文档的 `hub send` / `hub list` / `hub wait` / `hub jobs` 一律跑不了。发消息 `write agent://<Name>`（会唤醒空闲同伴）· 看回执 `read agent://<id>` · 查 job `read proc://` · 阻塞等结果用 `wait`。做完 idle，约 7 分钟后 parked；再 `write agent://<Name>` 唤醒，记忆还在。IRC **出不了这个进程**；两个 omp 窗口互发不了消息 → 跨进程用 `omp_dispatch.py`（`run` / `resume` / `status`，见本页开头），不要调用旧 `dispatch.ps1`。本机 `task.maxRecursionDepth: 2`（2026-10-15 上调；子代理可再开一层只读 child——brief 没写要开就别开）；个数上限 `task.maxConcurrency` = **0（无限）**（2026-09-30 曾降到 8；2026-10-15 Owner 令：**不限制**）。`config.yml` 是唯一可执行的事实（模型角色也在里面，不要背型号）。

**Codex**：用它自己的 subagents 和线程通讯：`/agent`、`/subagents`、`@` 提其它任务。跟进同一条线程，不要为了「再问一句」新开空白 child。跨家或另一个 Codex 窗口：走 `omp_dispatch.py`（见本页开头），不要另造入口。**不要改 Codex 这套机制。**

**Claude**：能开窗口时：跟进已有子代理用 `SendMessage` `to=agentId`（会唤醒）。不要每个切片都新 spawn。跨家：走 `omp_dispatch.py`（见本页开头；Claude 本机已卸载，不恢复旧入口）。

本进程里用自家 subagents 可以（Codex / omp 尤其如此）。

## 四道机器门（其余靠下面正文的规矩；另有 `gatecheck` 收尾对账，全量套数以 `run_all_gates.py` 的 `SUITES` 为准（2026-10-30 实测 24 套），本文不写死；`gatecheck` / `run_all_gates.py` 不在本仓库，见页首「伴生工具」）

> **三个门数不是同一件事，别拿它们互相校正**（2026-11-01 实测三个都对）：
>
> | 数 | 范围 | 查法 |
> |---:|---|---|
> | **7** | `guards.ts` 的 hook 门（`ai-attribution` / `recursive-delete` / `protected-process` / `unexpanded-temp-var` / `nested-bash` / `powershell-dollar` / `board-write`；`guards.ts` 不在本仓库，见页首「伴生工具」） | `grep -c 'guards.ts \[' ~/.omp/agent/hooks/log/*.log` |
> | **4** | 本页下表：派发流程的四道门 | 就是下表四行 |
> | **24** | `run_all_gates.py` 的 `SUITES` 测试套 | `python -c "import run_all_gates as r; print(len(r.SUITES))"` |
>
> 三者的关系：**7 是门（拦截），24 是测试（验证门有没有坏），4 是流程（什么时候该开单）**。

| 环节 | 谁拦 | 拦什么 |
|---|---|---|
| 派发前 | `board.py open` | 两个工人要写同一条路径 → 直接拒 |
| 派发前 | `briefcheck` | 缺 fence / 缺独占路径 / 缺可核对完成条件 / 落点不明 / 环境断言未标实测 → 拒（段内缺标注 → 警告；审计类 brief 缺报告四段 → 影子警告） |
| 收工时 | `board.py close --verdict ok` | 没带 `--verify`（真跑过的一条命令或一个真文件）→ 拒；带 `--receipt <回执文件>` 时首行必须 `STATUS: DONE/BLOCKED`（新门影子：缺省不拒） |
| 收尾 | `gatecheck` 派发对账 | 派出去了没收口的 → 点名 |

**档位（拿不准升档）**：T0 小改（单文件、无派发）免仪式；T1 常规派发 = 上表四门全走；T2 大波/多路（≥3 工人或跨家）再加：报告自审四段（Denominators / Findings / Self-audit / Summary）+ `close --receipt`。

## 父代 vs 工人：写权限边界（口头，但别自我说服）

父代**只读**项目文件。要改就派一个工人，改动在工人的 scope 里落地。这不是默认偏好，是硬规矩——不要因为「改动很小」「你说了可以」「我在 worktree 里」就自己动手。

| 操作 | 判定 |
|---|---|
| 读任何文件、搜、`git status` / `log` / `worktree list` | 父代可以 |
| 写 brief、写报告到非项目路径（如 `%TEMP%`） | 父代可以 |
| 改项目里任何被跟踪的文件 | **必须派工人** |
| `git commit` / `push` / 建分支 | **必须派工人**——父代不碰，工人收工后也不碰。父代要 push 就再派一个只带 `--scope <repo>` 的工人 |
| 把实现派给第二个工人 | **不许**（工人只能派一层，且那层不能再派） |

## 派发五步，一步都别跳

```
1  board.py open   --id <ID> --worker <名字> --scope <独占路径> --done "<一条命令或一个文件>"
2  写 brief（含 board: <ID>）
3  briefcheck <brief>          # 退出码非 0 就别派
4  同进程：task（CamelCase name）；跨进程：omp_dispatch.py（run / resume / status）；旧 dispatch.ps1 已删，不要调用
5  读 agent://<Name> / proc://<id> → 核 DONE WHEN → board.py close --id <ID> --verdict ok --verify "<真跑过的>"
```

**验收句的两条补充（2026-10-14 教训，见 `library/floor/incidents.md 第 15 个仪器`）**：
- **找不到 `last.md` ≠ 没交**——in-session 派发（`task` 工具）走 `async-result` 回投 + `agent://<id>` 可读，本就不写 last.md。三处都查（父会话回执 / `agent://<id>` / `proc://<id>` 终态）才是真没交。**回执读法按通道分两种**：同进程读 agent 返回，跨进程读 `ops/jobs/<id>/` 的 `last.md` + `receipt.json`——唯一写法见 `library/recovery/work.md §结论`。
- **超时实证**：`task` 工具的实际超时聚集在 2400s 一带（研究类工人常撞线）——派重活显式给 **≥3000s**，别用默认值。

`board.py` 在 `~\.omp\extra-hands\CACHE\board.py`，看板文件 `~\.owner\ops\board.md`，**只追加，永不改写**。

**参数速览（以 `--help` 为准，2026-10-15 实测）**：
- `open`：`--scope` 可重复；只读派发用 `--read-only`（免 scope、不冲突、仍对账）；影子参数 `--depends <ID,ID>`（等待行）、`--budget <N>`（探索类默认 12）、`--brief <路径>`。
- `close`：`--verdict ok` 必带 `--verify`；`--result` 写理由/去向（**`failed` / `blocked` / `abandoned` 三态必填**，2026-10-15 起硬门）；影子 `--receipt <文件>`（首行必须 `STATUS: DONE/BLOCKED`）、`--fail-code`（6 枚举：report-missing / acceptance-superficial / scope-creep / duplicated-work / stuck-loop / wrong-root-cause，只对 failed/blocked 有效，list 出月度统计）。

- `open` 缺 `--scope` 或 `--done` 直接拒。`--scope` **只收绝对路径**（`D:/...` 或 `/d/...`）——相对路径的含义取决于 cwd，没法跟别人的 scope 比，所以直接拒。
- **`--done` 不许自指**：别写「reconcile 无未收口」当完成条件——那一行自己就让 reconcile 非零，永远关不掉。写成一条命令或一个文件。
- `open` 撞上别人已占的路径直接拒，并告诉你谁占的。比较前会折叠 `.` 和 `..`、忽略大小写、认 `D:/x` 与 `/d/x` 两种写法；`/a/b` 和 `/a/bc` 判为不冲突（`b` 不是 `bc` 的父目录）。
- `close --verdict ok` 不给 `--verify` 直接拒。`--verify` 写**一个文件路径**时，工具会真去查它在不在——**这是机器拦的那一半**。`--verify` 写**一条命令**时，工具**无法**核实你跑没跑过，只把这句话记下来并在输出里明说「这一格靠你自己」。**别把命令那一半当机器保证。**
- 没跑过就写 `failed` 或 `abandoned`，别拿 `ok` 遮。`failed` / `blocked` / `abandoned` 都必须带 `--result` 写一句理由或去向（为什么失败 / 卡在哪 / 去哪了 / 被谁接了 / 为什么弃）。同一 ID 只能 `close` 一次；想重开就换 ID，**不要改写历史行**。（`blocked` = `failed` 的细分（卡在外部条件），三态同门同要求；别造第四种语义。）
- **测 board 一定要设 `BOARD_FILE` 指向 `%TEMP%` 下的假看板**，测完 `diff` 一下真看板确认没多行。看板是 append-only 的，探针行混进去删不干净。
  **这道门现在有机器执行了**：`board.py` 的 `probe_writes_production_board()` 在 `PYTEST_CURRENT_TEST` 非空或 `NODE_ENV=test` 且 `BOARD_FILE` 未重定向时**拒绝写生产看板**，`open` 与 `close` 都接了。测试 `CACHE/board.probe-guard.tests.py`（12/12）。
  **别用按名字过滤来替代它**：在 OPEN 行里 grep `probe|test-|assert|selfcheck|smoke|fixture|dry-run` 会大量误伤合法工单（实测 23 命中里只有 2 条是真污染）。
- **`briefcheck` 的 scope 门认散文行，不只认 `- ` 列表**——只认列表会把按本页模板写散文的 brief 全拒掉。测试 `CACHE/briefcheck.tests.py`（条数以 `ok N/N` 的 N 为准，2026-10-30 实测 102），改完必须跑。
- **绝对路径检查必须排在归一化前面**——先归一化会让 `relative/dir` 变成非空 `/relative/dir`，相对路径直接绕过这道专为它设的门。

## 工人模式（这一趟，不是身份）

brief 开头必须逐字是这一行：

```
YOU ARE THE WORKER.
```

> **工人 = 自主独立会话**（独立进程）：**跨进程无 IRC**（对派发方不等待、不尝试消息）；**进程内 IRC 是自己的**——可开一层子代理并与它们 IRC、自主做一切按需求的事；其子代理不许再开；对派发方的接口 = brief 进 / 最终答复出（跨进程入口重建后才恢复 `last.md` + 收据）。fence 全文见 `skill://dispatch`；机制见 `skill://coordination` §6b。

紧接着：

```
board: <ID>                      # 和看板上那行对上
# Report                      ← 报告落点单独一段，不要塞进 Acceptance
<报告写到哪个绝对路径>
# Target
<做成什么样算完>  目标路径写死，不要写「相关目录」
# Needs
write | bash | read-only            ← 这个工人拿到哪些工具。写不清楚就别派。
# Env-Claims                  ← 可选：对环境的断言只写这段，逐条标 [实测 <日期>] / [未验证]
- write 工具：可写绝对路径 [实测 2026-10-12]      ← 示例：断言原文 + 标注
# 口径对表                   ← 可选：引用 Owner 原话时必填——「要 X」一律带日期与出处（X04）
# Non-Conflict
- <本任务独占的写路径>           # 逐条列，board.py open 用的就是这些
# Change
<允许改什么 / 禁止改什么>
# Acceptance
DONE WHEN: <一条命令或一个文件>
# Stop-Search                ← 可选：探索类任务加这段（OpenAI context_gathering 配方）
<何时算探够了>  判据写死，例如：
- 能指名要改的具体内容 / 相关命中收敛到一处（约 70%）
- 绝对预算：最多 N 次工具调用（探索类默认 12）
- 逃生舱：到预算还没收敛，就按当前最佳判断继续做（"even if not fully correct"），不许回头问
```

**`# Stop-Search`（早停判据 + 调用预算 + 逃生舱三件套）**：不给早停判据，工人要么探到超时要么探得过浅。
与硬地板「禁止空转」互补：那条是负向禁令，这条是它的正向可执行形态。
**只对探索/调查类 brief 加**；实现类 brief 的 `DONE WHEN` 已经是终点，不必重复。

**重活另加「体量-方法-预算」段**（与 `# Stop-Search` 并列，只对重活）：
- **体量**：输入多大（GB / 条数 / 文件数）——写进 brief，别让工人自己撞上才发现。
- **方法**：允许怎么读（分片 / 首尾 N MB / 只要字段）——不许整份载入的写清。
- **预算**：分段落盘（每节一次 write，超时也不丢）+ **显式超时预算**（写进 brief；同进程 `task` 由父代 `wait` 收口，跨进程用 `omp_dispatch.py status --job <id>` 看回执）。

**这份模板的占位符填好后过 `briefcheck`。**
**但模板原样复制会被拒 4 项（`Non-Conflict` / `DONE WHEN` / `Report` / `Needs`）—— 这是设计意图，不是门坏了。**
`<报告写到哪个绝对路径>` 这类尖括号**必须换成真值**，包括「要写哪个绝对路径」这句话本身也不能留。
**规矩：要求工人落盘，就必须派有 write 的 agent；派只读的，
`DONE WHEN` 写给父代看，父代用 `cat "agent://<id>/report" > 路径` 落盘。**
report 门只认 `report/报告/回执/receipt/artifact/output` **六个**段名（`report_body`；自查 `grep -n report_body briefcheck.py` → :285，2026-10-15 重钉）。
`briefcheck.tests.py` 有一条 `doc/paifa-template-verbatim` 断言**填好值的同构模板**过门（exit 0），
另有 3 条分别断言去掉 `DONE WHEN` / `Non-Conflict` / `Report` 会被对应门拒。

`# Non-Conflict` 和 `DONE WHEN` 两段缺一不可，`briefcheck` 报 fail 就是不能派。

`RETURN:` 那一行**不是**必需的，别用它顶替 `# Report`——回条落点由 brief 的 `# Report` 指定；同进程用 `agent://<id>` / `proc://<id>` 收，跨进程读 `ops/jobs/<id>/receipt.json` → `final.last_md`（`<project>/<repo>/.owner/40-sovereign/EXECUTION-ADAPTER.md:80-90`）。

`# Non-Conflict` 只列**写**路径。读到哪里都行。列了父目录就会把子目录一起占住，所以列到你要写的那一层。

`DONE WHEN` 必须是**第三方能跑的一条命令，或一个能看的文件**。「做完了」「验证过了」不算。

**自审**：每个 brief 附 §自审 四段（A 早产出 → B 反驳 → C 机械验证 → D ≤14 行小结）；实现者不验收自己的产出。

**工人的最终答复第一行必须是 `STATUS: DONE` 或 `STATUS: BLOCKED`。**
`BLOCKED` 就写清缺什么、卡在哪、部分证据已落哪。**没有第三种**——**验收没全达成 = `BLOCKED`，不许写 `DONE`**；`DONE` 只给「全部验收项已证」——没有「一半 DONE」。
同一疑点推两轮还无新证据 → 直接 `BLOCKED` 写卡点；重复同一条命令 / 轮询 / `sleep` = 无新证据，不许空转重试（`library/recovery/work.md` 结论节同款）。
这一行只给直接叫你的人看。**下一个会话看不到它**，所以状态必须同时落到最终答复和看板上。

**长任务加两段前言**（官方 `tool_preambles` 配方；rollout 越长，这两段的差别越大）：
1. **开工前**：复述目标（一句话）+ 结构化计划（3-5 步）。父代看第一屏就知道你理解没理解。
2. **收工**：把「完成情况」与「计划」**分开**写——哪几项按计划完成、哪几项偏了、为什么。
   「与计划分开」是重点：混在一起写的完成汇报，父代没法对照计划发现偏差。

### 填 brief 的七个新坑

1. **`# Report` 之前不能有别的「报告」段。** `briefcheck` 的 report 门找**第一个**匹配的段名——
   若在 `# Report` 之前写了 `# 交付（报告结构）`，门读到的是那一段（里面没有路径）⇒ `[fail:report]`。
   **对策：`# Report` 放最前，或别的段名别带「报告/report」字样。**
2. **brief 里的报告路径必须写绝对路径。** 相对路径会被工人按自己的 cwd 解析错位置。
   **对策：所有路径从 `C:/` 或 `D:/` 写起。**
3. **语气 = 引导，不是口令堆**。工人读到的是「为什么做、要什么、边界在哪」；
   命令式只留给 `DONE WHEN` 与铁律。中间的过程让工人自己发挥，**那正是要买的东西**。
4. **附加材料要写明「在哪」。** omp `task` 派单的 `context` 会注入工人 system prompt 末尾的 `§ Context` 段——但工人**不保证会去那里找**（实测 2026-10-15：两个 i18n 工人各花 ~1 小时翻文件系统/父会话日志找「context 的术语表」，其实一直在自己系统提示里；巡检工人同类；全树取证见 `ops/research-2026-10-15-fleet/SUBAGENT-CONTEXT-2026-10-15.md`）。
   **父代侧**：引用附加材料必须写明位置——写「见你系统提示 `§ Context` 段」或直接写进 task/brief；**禁止只写「见 context 的 X」**。
   **工人侧**：拿不到输入时**先看自己系统提示的 `§ Context` 段**，再去找（禁止盲目全盘搜）。
5. **brief 里的数字一律带「截至 <时间戳>」。** 普查/计数类数字会漂（实例：87→119）；不带时点的数字 = 下一个人的错误引用源。
6. **Grok 三条**：① `grok -p` 的 stdout 在整段做完前为空——超时不得短于 15 分钟（重活 2700s 墙）；② 验收看**产物文件**不看 stdout（stdout 空 ≠ 失败）；③ 派发目录在验收前不清理。
7. **worker 首话三校验**（父代开工抽查）：① 首行是否 `STATUS:` 形态 ② 是否声称「没有文件系统/工具权限」（=换单）③ 是否出现 `｜｜DSML｜｜` 类伪标记（=换单）。

## 怎么把这几段填对

**唯一规格是上面那份模板**；`dispatch/SKILL.md` 与 `dispatch-brief/SKILL.md` 只做指向。四条规则：

- **`DONE WHEN` 不许用形容词。** `appropriate` / `named` / `relevant` 作为唯一规格是缺陷
  （实测：每次含糊验收都要再修一轮）。要写全：cwd、环境变量、选择器/套件名、期望退出码和断言数。
  同一份字节上已经跑过并被接受的长门，写 `do NOT repeat it`，并索要带修订号的沿用证据。
- **`# Report` 父代必须读得到。** 写到父代看不见的地方 = 失败的活。
  每条结论带 path+key 或产出它的那条命令；**贴验收命令自己的输出，不是你的转述**。
- **缓存规则（是工作守则，不是段落）**：留在这一趟里 —— **不 rewind、不「start over」、不换模型**。
  **纠正以下一条消息的形式到达，不是一份重写稿。**
- **回执在父代这边**：同进程 `task` 以最终答复（`agent://<id>`）+ 盘上产物为准；跨进程 wrapper 的回执 = `ops/jobs/<id>/receipt.json` + `last.md`（入口 2026-10-31 复核在位，见本页第 11 行）。收据只有一种读法与顺序：`<project>/<repo>/.owner/40-sovereign/EXECUTION-ADAPTER.md:80-90`（:88 定死 `receipt.json` → `final.last_md` → 实际产物）。（历史：2026-10-17 删 `dispatch.ps1` 后到入口重建前，这两份一度不可用。）
  父代核完产物或 diff，用 `write agent://<Name>` 追同一个工人，汇报时给 ask / 结论 / 下一步，
  不转述工人的散文。

看到 `YOU ARE THE WORKER` 就做 DONE WHEN，不要再派。
工人侧英文。对 Owner 汇报用中文。

## 自审（四段，每个 brief 附上）

每个工人 brief 都附这四段：A 早产出 → B 反驳 → C 机械验证 → D 小结。被推翻的结论从产物里删掉；实现者不接受自己的产出——验收换一个会话做（Owner r40，2026-10-13）。页尾的 ≤12 行复制块直接粘进 brief。

| 段 | 做什么 | 判据 |
|---|---|---|
| A 早产出 | 先写出能看的中间产物（文件、命令输出），再继续；不许把全部产出留到最后一刻 | 产物已落盘 |
| B 反驳 | 挑 3-5 条最强结论，逐条**试着推翻**；每条标 `CONFIRMED` / `WEAKENED` / `OVERTURNED` + 你跑过的那条命令 | 被 `OVERTURNED` 的结论已从产物里删掉或改写 |
| C 验证 | 指名一个机械检查器，**原样粘贴它的输出**（不许转述） | 输出是检查器自己打的 |
| D 小结 | ≤14 行：已确立 / 被推翻 / 未知 / 下一步 / 我仍赌错的是什么 | 五格都在 |

`WEAKENED` = 保留但收窄或加注；`OVERTURNED` = 删掉或重写。文件里不留被推翻的结论。

### 三条硬规矩

1. **实现者不验收自己的活**：`STATUS: DONE` 只说明「我这边做完」；验收由**另一个会话**做（不是干这活的本人），按 `DONE WHEN` 复核。见本页 §派发五步与 §工人模式。
2. **lead 记第一条**：每条工人结果，lead 记最终答复首行（`STATUS: ...`）和产物路径，不转述散文；状态同时落最终答复和看板。
3. **数字带分母和日期**：「查不到」不许写成「不存在」；「只有 / 全部 / 没有」要么配同轮全量检索，要么降级成「未确定」。见 `library/floor/incidents.md`。

### 机械检查器怎么挑

- 活自带门 → 跑那条门（`briefcheck`、`board.py close --verify`、项目自带测试），粘原文。
- 没有现成门 → 自己给一条能重跑、且对「结论为假」会失败的命令（能红才算测；例：`test -f` 对缺失文件退 1，`rule-hygiene.py` 对死路径报 RED），把它的真实输出粘上。
- 检查器可疑 → 换一台仪器再测一遍；两台输出不一致本身就是发现（见 `library/floor/incidents.md`）。

细则：本页（工人模式与回执）· `library/recovery/work.md`（证据与结论）· `library/floor/incidents.md`（复核方法）。

### 给 brief 的复制块（≤12 行）

```
# 自审（四段，做完再交）
A 早产出：先落盘能看的中间产物，再继续。
B 反驳：挑 3-5 条最强结论逐条试推翻，标 CONFIRMED/WEAKENED/OVERTURNED + 你跑的命令；被推翻的从产物里删掉。
C 验证：指名一个机械检查器，原样粘贴它的输出。
D 小结（≤14 行）：已确立 / 被推翻 / 未知 / 下一步 / 我仍赌错的是什么。
数字带分母和日期；「查不到」不写成「不存在」。
验收由另一个会话做——你不验收自己的产出。
干净上下文：验收者只拿 DONE WHEN + 产物路径 + 目标，不带工人的理由/transcript——工人自述不算证据。
门的负控：新门先证明它能为红样本变红——不能变红的绿门 = 假门（一次复审据此抓出 9 个缺陷）。
文档数字用契约测试钉死（改了数字就红）——没钉的计数按过期处理。
```

## 多路派发（任务图 / 前沿 / 并发与收齐）

派 subagent 必须编排好：任务不能冲突，边界要清楚。派之前先有**任务图**，派的时候只派**前沿**，brief 用**指针**不复制。

1. **先切互不重叠的 scope，再派。** 切法：按目录、按文件、按问题维度。切不出互不重叠的 scope，说明这个活不该并行，该串行。
2. **一个 scope 一个工人。** 撞路径 `board.py open` 会拒，别绕。
3. **任务图与前沿。** 一波多工项时，先在 PLAN 里给每项写 `blocked by`（互不重叠的 scope 才可并行）；板上对应 `board.py open --depends <ID,ID>`（影子参数）登记等待边。**前沿（frontier）** = 现在就能派的集合：**阻塞全清 + 未被占坑 + 没人在做**。派发只从**前沿**取；**收一个 close 一个，再取下一个前沿**——不是把整张图一次铺出去。「想开干的冲动」= 你可能在跳过阻塞边。
4. **并发不设人为上限。** 上限 = `config.yml` 的 `task.maxConcurrency`（当前 0 = 无限，2026-10-15 Owner 令）= 不设天花板。真正的风险不是数量，是**没写报告落点、没逐个核回执**。历史教训：fan-out 12 / 12 / 6 个**交付 0 份报告**，原因是「不写落点、不逐个核」，不是「派多了」。一波发 8 个时，把每份 brief 的 `# Report` 绝对路径写死；收工时先 `ls` 盘上有没有文件，再 `read` 核首行 STATUS——这两步比限制数量有用得多。
5. **只读派发用 `--read-only`，不要占 scope**（占太宽会挡掉所有别的只读派发）。`board.py open --id X --read-only --done "<父代怎么验>"` **不占写路径、不与任何人冲突、但仍记账可对账**。
6. **每个 brief 自足。** 工人看不到你的上下文，也看不到别的工人的 brief。要什么写全，别写「同上」「参考刚才那个」。但**背景与实现细节用指针**——给路径 + 要读哪一段（PLAN 的哪节 / 报告第几段 / 哪个 skill），**不把 PLAN 内容抄进 brief**。复制品会与 PLAN 漂移；父代与工人的通信要稀疏：靠指针 + 回执，不靠来回解释。
7. **能重活交出去、别把重活留给自己。** 但**判断留给自己**：重活是「跑 500 条命令统计」，判断是「哪 5 条说明问题」。`board.py`、`gatecheck.py` 这类已经能一条命令出答案的，不要派工人。
8. **回执逐个核。** 父代读完每个 worker 的最终答复（`agent://<id>`）就立刻 `board.py close`，别攒到最后——攒着就会出现「派了 6 个，2 个没回，忘了」。
9. **同产物多路复核 + per-item 判决**（高风险产物）：派 2+ 路独立复核（不同工人或不同模型族），每条结论给 `CONFIRMED / WEAKENED / OVERTURNED` 判决；验收与实现分离（<project-a> 的 workflow.md 第 9 条；<project-b> 六路复核先例）。
10. **一波收工三件**：全部 close 后——① 板对账（`reconcile`/`gatecheck` 无未收口）② 收据抽验（父代复跑 `--verify`）③ 覆盘一页（`library/recovery/retro.md`，影子）。

## 断供 / 冷却（派发中途）

后端报错（冷却 / 熔断 / 401 / 503）= 断供判据，按实际报错处置，**不推算额度**：

1. **停止补发**：这一波不再新增派发；在飞的先落盘（产物 + 最终答复），去向写进看板行。
2. **换通道只用既有配置或 Owner 已明确批准的模型**（**r43/r44 落定**：常备默认 = 脚本默认 `<provider>/deepseek-v4.1-flash` max——不限量、含联网/chrome/长任务，该线实测交付 58/60，可同时开多个当智囊团；`<provider>/glm-5.3` 拆小任务当智囊团，额度耗尽自动退 deepseek（Owner 设的安全网）；gpt6.1sol 等 Owner 通知、不用；真难题才加 Opus 5.5 / Sonnet 5.5 的 xh/max，一次一件（Pro 5h 窗）；**派前必 `modelcheck.py`、验收必 `servedmodels --expect`（以伺服端实际回答者为准）**）；不加其它贵档、新账号 / 新服务或付费兜底。续接保留原任务与已读上下文。
3. **恢复证据**：Owner 明说恢复，就按原任务续跑，不反复探测确认；否则一次成功的原任务续跑也可作证。不刷健康探针、不无限 retry、不整波重派。
4. **题材 → 后端**：cyber-adjacent / 政策敏感题材**不派 Opus**（实测交付 4/15；deepseek 58/60、glm 6/7）——此类题材走 <provider> 线，省得撞拒绝。（`SYNTH-02 §I22`）

## 恢复、旧会话、回执

这三件写在 brief 里，不靠工人自己猜。

1. 同进程跟进用 `write agent://<Name>` 唤醒原工人；跨进程续接用 `omp_dispatch.py resume --job <id>`（旧 `-Resume` 是已删入口的历史参数，不要调用）。宿主重启 / 工人被杀后的收口（先核盘上产物、可续先续、不可恢复才链接式换 ID）见 `library/recovery/recovery.md`。不要为了续上一句新开一个空白工人。
2. 工人如果会被压缩，最终答复**第一行 = `STATUS: ...`，第二行**写：原话要什么，还开着什么，下一步是什么。协议是 `library/recovery/recovery.md`。不要读 `mandate.md`，除非 Owner 点名要历史。
   **汇报模板（omp/claude/codex 三家统一，2026-10-16）**：`STATUS 首行 → 结论/数字 → 证据三件套 → 未做项与下一步 →（可选）口径冲突表`。（`SYNTH-03 §3.6-5`）
3. 要读以前的会话：有人点名一条（id / URI / 路径）就 `sessread <id>` 直读；只有关键词就 `sessq q "<词>" --limit 3 --budget 2000` 找，索引没有先 `sessq build`。不要整份读 jsonl。brief 里写清要读哪条、要查哪个词。（`sessq` / `sessread` 不在本仓库，见页首「伴生工具」）
4. 写完 brief 过一遍 `briefcheck`（九项：fence / 独占写路径 / 完成条件 / 报告落点 / 反斜杠 / `read` / `needs` / `env` / `board`；全表见 `library/tooling/tools.md`）；**退出码非 0 就别派**。反斜杠被转义吞掉时工人会拿到盘符相对路径。
5. 同进程 `task`：最终答复非空 / 产物在盘上 = **有回条**，不是任务完成；还要核当前产物和 DONE WHEN。跨进程 wrapper 的回执 `receipt.json` + `last.md` 在 `ops/jobs/<id>/`，入口 2026-10-31 复核在位；`exit 0` 只覆盖 `DONE` 与 `DRY_RUN`，先看 `receipt.status`，顺序只有一种：`<project>/<repo>/.owner/40-sovereign/EXECUTION-ADAPTER.md:80-90`。
   `report_missing=true` / `out_bytes=0` / `timed_out` 是跨进程历史字段；同进程 `task` 失败按 worker 最终答复 `BLOCKED` 或缺产物处理。receipt 仍报 missing 才重派或换后端。
6. **父代收工复跑**：`close --verify` 写的是父代真复跑过的命令/文件，不是工人自述；复跑结果与工人回执不一致时以复跑为准（某仓 79/122 VERIFY 行明写父代复跑，含推翻父代前提的案例）。

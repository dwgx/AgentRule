<!-- source: AgentRule/恢复.md @ 8b1222d4 -->
# 恢复
> EN: After compaction, resume or a new window: find the board, check it against disk, and hand off with the five-part template.
<!-- summary: 压缩、重启或新窗口后，怎么找到板、核对磁盘、按五段模板交出去。 -->

> 伴生工具：本页提到的 `<sessq, omp_dispatch.py, gatecheck>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

压缩、resume、新窗口都不是新任务，也不给新授权。Owner 最新的一句改掉它点名的那一条，其余还在。

1. 先写恢复句：原话要什么，还开着什么，下一步是什么。**给父代交卷时（工人模式）第一行 = `STATUS: ...`，恢复句放第二行**（`library/dispatch/dispatch.md`）。

2. 只补一个缺口。**找板的顺序**：

   1. 项目根的 `HANDOFF.md` / `NOW.md` / `.codex/HANDOFF.md` / `.claude/NOW.md`
   2. `~/.owner/ops/boards/registry.json` 的最长前缀匹配
   3. 该项目**子目录**里叫 `HANDOFF*` / `NOW*` 的文件
   4. 一条 `sessq q "<词>" --limit 3 --budget 2000`（`sessq` 不在本仓库，见页首「伴生工具」）

   **只查根一级会误判**（实测）：`<project-h>` 的板在
   `<project-h>/.agent/HANDOFF_OMP_20261002.md`，另一个项目（整棵树在另一个盘）的在 `docs/HANDOFF.md`，
   两者根目录都没有那几个名字。**registry 是这一步的主要落点，不是兜底。**
   （2026-10-13 更正：原例两处路径已不存在——前者迁入 `<project-h>/` 子目录、后者换了盘；registry 两条键都在。）

   **读完板，先跑板上给的核对命令，再决定信不信。**

   **板的合格线（三字段）**：未完成项清单（每项带核对命令）· 当前焦点 · 已知坏在哪——缺字段的板先补再信；只写单句「下一步」挡不住「宣布完工」这个失败模式。

   为什么它最要紧：板是「写完那一刻」的快照，不是真相源。四个项目**全中**过，形状都是同一种——板上的数与盘上的数差几位：

   ```
   <project-a>  板写 68,425 行 / 19 通道，盘上 68,428 / 20
   <project-b>  板写 HEAD=612802a，实测 274278b
   <project-c>  .agent/HANDOFF.md 的 board_head 落后真实 HEAD 18 笔
   <project-d>  板写 113 事实 / 89 形式，实测 115 / 89
   ```

   （上面是**假例**：项目名已替换，数字保留只为说明「差几位也是差」，不要引用。）

   **指针还可能指向不存在或已归档的东西，比指向过期的更糟**：`<project>\<repo>\NOW.md`
   **不存在**，而 `extra-hands/THINK/mandate.md` 多处称它 "the sole live handoff"（2026-10-13 实测逐字 2 处）；
   `extra-hands/README.md` 也曾把 `THINK/handoff.md` 排在恢复链第二位，而该文件第 1 行
   自称 `# ARCHIVE — not the live handoff`。

   **可执行的判据**（不是散文）：板上一般带核对命令，没有就自己 `stat` 一个它点名的路径。
   对不上就**以盘上为准**，并在回来里说一句。**先 stat，再读内容。**

3. 不要读 `~\.omp\extra-hands\THINK\mandate.md`，除非 Owner 点名要历史。不要整份读 jsonl。

**3b. 恢复协议由谁注入、何时到（2026-10-14 实测）**：
- **SessionStart hook 只发指针**（163→458 字符：板路径 + 一句「先复述」），**不发全文**；
- **omp 的 compacting 注入完整 `[RECOVER/1]` 块**（含规则清单）——所以压缩后看到的「规则回来了」是注入，不是记忆；
- **压缩注入只做 bounded checkpoint/recovery**：`[RECOVER]` 是「继续」信号，不是收工/交接信号；`delivered:true` 只证明注入发出，不证明模型已读。第一次、第二次压缩都照常继续原任务。
- 其余家（claude/codex）由各自 SessionStart 配置决定；**没收到注入 ≠ 协议不存在**——按本页顺序自查（找板 → stat → 读三字段）。

4. **任务真正收口时**，把项目自己的那块板改成**三字段**：未完成项清单（含各自核对命令）+ 当前焦点 + 已知坏在哪。
   没有项目板就不要改机器流水账。
   维护运行登记册（`runs/README` 这类多轮记录）时：过期不删、标 `SUPERSEDED` 并指向当前那份——读者要能一眼看出哪个是当前（<repo> 148 份 md 里 ~40 个 HEAD 值没有一处说明谁现行）。

   **交接的落点也有坑**：项目内写 `HANDOFF.md` ＝ 未点名改
   `<project>`；写 `~/.owner/ops/HANDOFF-*.md` 会按 `newestMatch` 抢掉机器级恢复落点
   （见 `ops/boards/README.md`）。**辅助文件一律叫 `detail-<date>.md`；只有板才叫
   `HANDOFF-<date>.md`。**

**收工触发（2026-10-19 对齐）**：只有 Owner 明说收工/交接/封存、任务验收完成、或一波派发全部 close 时才走 `shougong`。压缩次数（1 次 / ≥2 次）不是触发条件；`[RECOVER]` 只做恢复句 + 继续。

5. 快到上限别硬压：压缩过 2 次、或单会话跨天，**照常继续**（压缩兜底；不向 Owner 提「开新会话」）；要交接时写五件——
   契约、当前状态、已定决策加理由、走过的死路、唯一待解问题（五件，不带 transcript）。

   **五件交接模板（2026-10-16 起，照抄填写；先例 = <project-e> 25 份 handoff，同构）：**
   - `## Goal` — 一句话：要什么；goal-mode 目标原话。
   - `## Constraints & Preferences` — 红线与偏好（只读范围 / 禁项 / 纪律：数字带分母、落盘优先）。
   - `## Progress` — `### Done`（已完成：一句话 + 证据指针）/ `### In Progress`（在飞：单名 + brief 路径 + 报告落点 + DONE WHEN）/ `### Pending`（未派：按依赖排序）。
   - `## Key Decisions` — 已定决策 + 理由（防止下一手重推）。
   - `## Critical Context` — 恢复必需：关键路径 / 关键数字（带口径）/ 口径陷阱 / 工具与脚本位置。
   - 纪律（X04）：**Owner 原话区一律带日期与出处**——口径是流式的（自我覆盖），没日期的「他要 X」= 下一个人的错误引用源（`SYNTH-03 §3.6`）。
   - 落点：会话目录 auto-handoff（压缩时自动落）或项目内 `detail-<date>.md`（命名规则见第 4 条）。

**5b. 阈值自管（2026-10-16 起，ctx-watch hook）**：
- 本机已装 `ctx-watch` hook（`~/.omp/agent/hooks/post/ctx-watch.ts`）：上下文跨过 **40 / 45 / 48%**（= 自动压缩阈值 50% 减 10/5/2）时，你会在消息尾部收到一条
  `[ctx-watch] 上下文 xx% → 自动压缩 50%。…` 通知（每档只发一次；压缩后自动重新武装）。
- 收到后按档执行（**都是「继续干」的提醒，不是停工信号**）：**40%** 少开新大读、状态落盘；**45%** 照常推进，压缩自动兜底（auto-handoff 自动落盘、压缩后按恢复链续跑）；**48%** 准备压缩；**50% = 自动压缩**。没有 35% 档。**不要停工收工/交接、不要向 Owner 提「开新会话」。**
- 原则不变：**别硬压、别停摆**——正常推进即可；**收工/交接只在 Owner 点名或任务真正收口时做**；交接落 `detail-<date>.md`（落点规则见第 4 条）。

6. **宿主重启 / 工人被杀之后**（不是新任务、不给新授权）：

   1. 先 `board.py reconcile`（`gatecheck` 查同一面；该工具不在本仓库，见页首「伴生工具」）列未收口。
   2. 每单按 **`DONE WHEN` 验收盘上产物**——已通过 → 只补缺失报告；只是存在、仍不合格或部分完成 → 续原 worker。文件存在不等于任务通过。
   3. 原 worker 会话**可续就先续**：跨进程用 `omp_dispatch.py resume --job <id>`（该工具不在本仓库，见页首「伴生工具」），同进程在跑的用 `write agent://<id>` 唤醒；brief / 验收不变，复用已读上下文。
   4. **证明不可恢复**（会话文件坏 / 上下文已丢）才派新单；新单**链接旧单**——board result 写清去向，旧会话与旧看板行**不删**（那是链路）。

## 项目状态指针（不在此页存内容）

机器级恢复只答「怎么恢复」；项目当前状态一律读项目自己的板 / 证据目录，别在这里存副本。

| 项目 | 读这里 |
|---|---|
| <service-a> | `<project>/<service-a>/PLAN.md`（项目自己的计划；根目录没有 `HANDOFF.md`，别去找） |
| <ops-vault> / ops | `~/.owner/<ops-vault>-KB/`（vault；`ops/boards/<ops-vault>.md` 不存在） |

**为什么搬走**：这页是每个压缩会话第一个读的文件；项目数字每天漂，留在这里等于让所有会话读一份过期快照（2026-10-30 审计：4 条失效引用使 `rule-hygiene` 判红）。原 92 行逐字迁到 `<reports-dir>/agentrule-audit/recover-project-state-20261030.md`（原文件 sha256 见 `backup-SHA256.txt` 的 `library/recovery/recovery.md` 行；要长期保留就把它挪进 `~/.owner/ops/boards/`）。

<!-- source: AgentRule/写给agent.md @ 0b19c0ff -->
# 写给 agent
> EN: Criteria for any document an agent consumes — rule pages, skills, briefs: pointers, context load, pruning, completion criteria, positive phrasing.
<!-- summary: 写任何 agent 要读的文档前的判准与反例：指针、上下文成本、删减、完成条件。 -->

> 一句话：写或改**任何 agent 消费的文档**之前读这页——判准＋反例。它不是要跑的会话，是一页判准。
> 适用：`library/*`、`SKILL.md`、`RULES.md`、brief、被指针指到的文档。给 Owner 看的文本另过 `library/dispatch/reply-shape.md`（结论先行、无代号、翻译纪律）。

## 0 · 怎么用：三问自检（每一句都过）

1. **no-op 测试**：这句改变行为吗（相对模型的默认）？——判准是**模型相对**的，靠**跑**不靠辩；说得出它管住哪个分支就留，说不出就**删整句**（不是修词）。两人争一句是不是 no-op，争的其实是「默认」，跑一遍文档裁决。
2. **正面改写**：这句是禁令吗？——能写成目标行为就改写成正面句（§6）。
3. **收词**：这是同一个意思的第几处展开？——≥3 处展开，收成一个 leading word（§5）。

## 1 · 上下文指针

指针 = 「这是什么」+「什么时候到达它」（**分支条件**）。触发可靠度由**措辞**决定，不由目标决定——must-have 的材料配弱措辞＝触发不可靠的缺陷（variance bug）。**先磨措辞，不行才内联。**

- 判准：一行指针能不能答「什么情况下我会打开它」？同义词列一串但其实是同一个分支 → 合并成一个。
- 反例：指针指向**不存在或已归档**的靶子（比指向过期的更糟）——`origin/NOW.md` 不存在，而 `mandate.md` 多处称它 sole live handoff；`THINK/handoff.md` 第一行自称 `# ARCHIVE`，却曾被排进恢复链第二位（`library/recovery/recovery.md` 有记录）。
- 好例：`library/tooling/skills.md` 的导览表 = 全是指针，行行写「什么时候想到它」；全新会话 3/3 实测能照它答对（`library/tooling/skills.md` 已实测节；「想起来后会不会真去读」未测——别把未测的当已测）。
- 常驻的每个字每轮付费（§2）：指针是常驻里最值钱的行，先磨它。

## 2 · 两种负载

- **context load**：常驻材料每一轮都花 token 与注意力（`AGENTS.md` 行、skill description、任何每轮在上下文里的东西）。
- **cognitive load**：人记得住的页数、什么时候去够哪页——**人是索引**。这不是要最小化到零的负载（人的判断力花在这），但不许无谓堆积。

判准：新加的每一行先问「它住常驻还是按需？」住常驻的要能证明每轮都值。**常驻只放铁律和入口；步骤与细节下推。**

- 本机锚：`library/README.md`「目录不是百科」；LLM 生成 context file 实测 **−3% 成功率 / +20% 成本**（四触发的立项依据）。
- 本机测量：缓存输入 = 鲜输入的 2%（`cache-hygiene`）——但新增常驻行会打穿前缀，重新按鲜输入计费。

## 3 · 信息阶梯与剪枝

一页 = **步骤**（按序动作）＋**参考**（按需查）。三层阶梯：页内步骤 → 页内参考 → 下推参考（指针之后，按需加载）。

- **分支测试**（何时下推）：每个分支都要的**内联**；只有部分分支到的**下推**。
- **同置**：一个概念的定义、规则、例外住同一标题下——读一段把邻居一起带进来。
- **单一真源**：一个意思只住一处；副本会漂移。先例：Grok 的 `recover.md` 从抄写版改成**指针**（不存副本；机器检查 = `gatecheck` 的 `FLOOR_POINTER`，该工具不在本仓库，见页首「伴生工具」）——**该检查今天恒跳过**（`~\.grok` 未安装，两条目标都不在位），别把它当成「已被机器盯着」的证据。
- **环境是源**：`--help`、config、目录布局能查到的**别抄**——文档只存查不到的（不成文惯例、选择背后的理由、配置不承认的坑）。
- **防沉积**：加安全、删危险 → 层层层积（sediment）。**每条新规则/新配置/新脚本配一个「删条触发条件」**（`rule-hygiene.py` 查覆盖）。
- 反例：蔓延（sprawl）——每行都活、都真，但太长，注意力被摊薄；「只加不删是本机最常见的慢性失败」（`library/floor/hard-floor.md`）。

## 4 · 完成判据

每个步骤一个**出口**；出口两性：**清晰**（分得清做完没做完）＋**要求量**（逼出足够的活）。

- 判准：能从「没做完」里区分出「做完了」吗？最强者 = 可机检＋穷尽（「每一个 X 都…」）。
- 本机形态：`DONE WHEN` = 一条命令或一个文件；**形容词当唯一规格 = 缺陷**——`appropriate` / `named` / `relevant` 已实测「每次含糊验收都要再修一轮」（`library/dispatch/dispatch.md`）。
- 模糊出口会招**早收**（premature completion）：后面没做的步骤在拉你收工，出口的清晰度是唯一的阻力。

## 5 · leading word

用一个**预训练已有的词**当行为锚：重复「词」不重复「句子」；一个词收一整个区域的行为。

- 本机词表：**板**（独占写路径登记）· **门**（机器拒绝）· **收据**（跑过的证据）· **落盘**（写下来才算）· **影子**（先只记录不动手）· **前沿**（前提已定的问题集）· **占坑**（board open）· **两轴**（评审的两个维度）。
- 判准：三处在展开同一个意思 → 收词。「快速、确定性、低开销」→ **tight**；「先跑一段只记录不动手」→ **影子**。
- 反例：自造词不给定义、也不借先验——你付定义费，它一个先验都不还。

## 6 · 否定是反模式

禁令把**被禁的行为**拉进上下文，反而更可得（「别想大象」）。目标行为写**正面句**。

- 判准：这句能不能改写成「要什么」？能就改。
- 例外：**硬护栏**（有执行层的门、`library/floor/hard-floor.md` 的禁令清单）可以留否定——但配一句正面目标。
- 现状核查（2026-10-21 复核 `hooks/pre/guards.ts`）：7 道门的 reason **多数已带正面解法**（`recursive-delete` 给「temp 内删，或经 Owner 归档」；`nested-bash` 给全路径写法；`powershell-dollar` 给单引号写法；`unexpanded-temp-var` 给 `$TEMP` 写法；`board-write` 给「`board.py` 或 `>>` 追加」）；`protected-process` 仍是纯否定＋理由。
  → 待做实验收窄为：**只改缺正面目标的那几条**（`protected-process` 优先），跑 `hook_probe.py` 比对 hook 日志分桶的 delta（该工具不在本仓库，见页首「伴生工具」）；拦截行为不变而 token 降＝机制被本机实测支持，不变记 `[UNVERIFIED]` 不推广。

## 7 · 技能专项

> omp 的具体 frontmatter 字段、skill 目录位置与调用语法见 `adapters/omp.md`；本节只留各家通用的判据。

- **frontmatter**：`name` + `description`（native provider 必需）。`disable-model-invocation: true` = 只有人能叫（零常驻成本，但吃认知负载——必须靠 `library/tooling/skills.md` 指针补发现）。
- **调用选择**：模型要能自己找到（或别的技能要拉它）→ 常驻 description，写**触发分支**；只人手动的 → 隐藏。
- **description 写分支，不写简介**：它占每轮成本、只帮「发现」，所以列「什么时候用」的条件；内容摘要留给 `library/tooling/skills.md`。
- **组合型技能 = 一行壳**（「调 X 和 Y」）；重内容住原语（先例：`grill-with-docs` 一行 → `grilling` + `domain-modeling`）。

## 8 · 事故引用（每页自证）

写新规则页 / 改旧页时，**每条机制尽量配一次本机真实事故**（引 `library/floor/incidents.md` / `library/dispatch/dispatch.md` / `library/README.md` 的具体条目）——没有事故引用的机制句，下一个 AI 会把删掉的东西加回来。

| 机制 | 本机案例（出处） |
|---|---|
| 指针 | `origin/NOW.md` 不存在仍被称 sole live handoff；`THINK/handoff.md` 自称 ARCHIVE 却被排进恢复链（`library/recovery/recovery.md`） |
| 单一真源 | Grok `recover.md` 抄写版 → 指针（`library/README.md`） |
| 完成判据 | `DONE WHEN` 形容词（`library/dispatch/dispatch.md`）；「一个永远绿的检查比没有检查更糟」（`library/floor/incidents.md` ④） |
| 沉积 / 只加不删 | 2026-10-13 清 18 份备份；2026-10-14 误删 19 份（`library/README.md` 备份保留节）——删前先打印名单＋引用数 |
| 负载 | LLM 生成 context file −3% / +20%（`library/README.md`） |
| 否定 | 6 道 hook 门 reason 现状（§6；`protected-process` 缺正面句） |

**删条: 3 个月内没有一次「照它砍掉某页的一句话」的实例 → 降为附录（记录降级理由）。**

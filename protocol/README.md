# 协议

> EN: Where to start reading, and which of the six pages decides your question.

这六页是换 harness 也不变的判据：哪些事不能做、活怎么交、门怎么算数、断了怎么接。某一家怎么落地看 [`../adapters/README.md`](../adapters/README.md)，每条规则的来历看 [`../library/README.md`](../library/README.md)。六页都是白话文，按需打开，不要预载。

## 六页

| 文件 | 决定什么 | 什么时候读 |
|---|---|---|
| [`00-floor.md`](00-floor.md) | 十条不许做的动作；违反任一条，这一轮停下改做法 | 开工前；想说「这次特殊」之前 |
| [`01-status.md`](01-status.md) | 交活首行只写 `DONE` / `BLOCKED`，以及 `DONE` 必须满足什么 | 交活前；收到工人答复时 |
| [`02-dispatch.md`](02-dispatch.md) | 开卡 → 写 brief → 过检查 → 派 → 收卡，五个动作与证据要求 | 派活前；接活前 |
| [`03-gates.md`](03-gates.md) | 一道门由哪四样构成，一条规则能不能机器判、怎么负控 | 写门、审门，或同一条规则第二次被违反时 |
| [`04-recovery.md`](04-recovery.md) | 压缩、重启、新窗口之后怎么接上：一句话复述、核板、只补一个缺口 | 新会话、resume、上下文被压缩后 |
| [`05-memory.md`](05-memory.md) | 记忆只给启发、盘上才是事实；改共享文件的五步 | 写数字或状态前；改规则书、配置前 |

## 阅读顺序

- **新读者**：`00-floor` → `01-status` → `02-dispatch`。先知道哪些事不能做，再知道什么算交完，最后才是把活交给别人。三篇合计约一百七十行，半小时内能读完。
- **要派发的人**：`02-dispatch` → `03-gates` → `04-recovery`。brief 的判据在 `02`；哪些规矩值得做成门、门怎么写才能红，在 `03`；一波收工后下一波怎么接上，在 `04`。
- **只想知道「为什么」**：直接进 [`../library/`](../library/README.md)，那里按事故归档，只读不预载——理由见 `05-memory` 第 2 节。
- **落地到具体 harness**：先读 [`../adapters/README.md`](../adapters/README.md) 分三家的差异，再进单篇。

## 边界

- 这六页只写判据，不写日期和事故编号；要追来历去 `../library/`。
- 门要有执行位置和退出码；本仓库只发判据，不替你装门。装法见 `../adapters/`。

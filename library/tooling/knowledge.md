<!-- source: AgentRule/知识.md @ d1a49a2b -->
# 知识维护（不再考古）
> EN: Keep a per-project knowledge ledger instead of re-reading transcripts: append one seven-part block when you finish, merge on a threshold, never read raw jsonl.
<!-- summary: 每个项目维护一份知识台账，收工追加七段一块，到阈值再合并。 -->

> 伴生工具：本页提到的 `<append_session.py, merge_sessions.py>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

> **摘要（5 行）**：① 每个项目两个入口：`<项目>/_agent-history/WORKFLOW.md`（现状，接手只读 `## 0.` 块 ≤60 行）与同目录 `SESSIONS.md`（台账，只追加）。
> ② 收工必写：做这件事的 agent 自己追加**一块**（交卷前 / 项目收口 / 板行 close 之前，任一即写），七段 Goal/Done/Decided/Open/Pit/Blocked/Verified。
> ③ 硬上限 2,000 字符 / 40 行；超了脚本 exit 2 **拒写**，压缩后重写，不许静默截断。
> ④ 合并阈值：台账 ≥10 块 或 最老未合并块 ≥30 天 或 >400 行 → **下一个真正接手的 agent** 合并，不是知识专岗。
> ⑤ 会话库是证据不是知识：默认不读 jsonl；只在 WORKFLOW 写明「需回原始会话」且 Owner 点名时才读。

工具装在 `~/.owner/ops/kb/tools/`（`append_session.py` 写、`merge_sessions.py` 只读体检；这两件工具不在本仓库，见页首「伴生工具」），用法见 `~/.owner/ops/kb/README.md`。本页只管这条回流通道，别的规矩不复述。

## 写（收工追加一块）

- 谁写：做这件事的 agent 自己写。代写 = 二手转述，代写者还得先考古。
- 何时写：任一即写，**一次会话只追加一块** —— ① 工人交卷前（`STATUS:` 之前）② 项目验收 / 收口 ③ 板行 `close` 之前。
- 命令（先 `--dry-run`，无副作用）：

```bash
T=~/.owner/ops/kb/tools
python $T/append_session.py --template                                  # 七段骨架
python $T/append_session.py --project <DIR> --summary-file s.md --dry-run
python $T/append_session.py --project <DIR> --summary-file s.md --board <ID> --session <agent>
```

- 落盘判据（脚本自己打印）：`APPENDED sess:<sha10> -> …\SESSIONS.md (N chars / M lines, block #k)` = 写成功；`SKIP already present` = 同一摘要重复提交，正常，不用重试。
- 拒写判据（exit 2，**不截断**）：缺 Goal/Done/Open/Verified；>2,000 字符或 >40 行；项目名歧义或不存在；没有 `_agent-history/` 且没给 `--create`。压缩摘要后重写，别绕脚本。
- 七段：`Goal` 1 行（不复述背景）· `Done` ≤5 条带证据指针（文件 / 提交 / 命令）· `Decided` ≤3 条（决定了什么 + 为什么）· `Open` ≤3 条**各带核对命令** · `Pit` ≤2 条（死路）· `Blocked` ≤2 条（卡在哪 + 缺谁裁）· `Verified` ≤3 条**实际跑过的命令**，没跑就写 `[UNVERIFIED]`。
- 不写：transcript / 工具输出原文 / 密钥 / AI 自评 / commit 流水 / 环境版本号（除非这次变了）。台账会进 git 与备份。

## 合并（阈值 + 谁合并）

- 提示命令（每次追加后跑一次；只打印不写盘，`exit 1` = 该合并）：

```bash
python $T/merge_sessions.py --project <DIR>     # 0=OK 1=MERGE NOW 4=接手块有缺陷
python $T/merge_sessions.py --audit             # 全项目一张表（只读）
```

- 触发（任一，输出即判据）：台账 **≥10 块** ／ 最老未合并块 **≥30 天** ／ `SESSIONS.md` **>400 行**。看到 `verdict : MERGE NOW  [blocks 10 >= 10]` 就是到了。
- 谁合并：下一个真正接手该项目干活的 agent —— 不是知识专岗（只有干活的人判得准「哪条还成立」）。
- 删留映射：`Goal` 丢弃（已被 Done 概括）· `Done` → WORKFLOW 的 §3（≤15 条，每条留一个证据指针）· `Decided` → §8（带日期，只增）· `Open` → §4（带核对命令，已解决的删掉或降级成 §3 一行）· `Blocked` → §5（带原因 + 缺谁裁）· `Pit` → §7（去重 ≤12 条，同坑记次数）· `Verified` 只留命令、输出丢弃 · `cwd`/`git` 覆盖 §2（不累积）。
- 先归档再收缩：块原文逐字节进 `SESSIONS-ARCHIVE-<YYYYMM>.md`，核对字节数 ≥ 源，再把台账收缩为「表头 + `<!-- merged: -->` + 最近 3 块」。

## 读工具输出（判据码）

- `merge_sessions.py` 退出码：`0` = 干净 · `1` = 该合并 · `4` = 接手块有缺陷（台账本身可能没事）· `2` = 参数 / 根目录不对。
- `takeover :` 行六种红：`NO-WORKFLOW`（没有 WORKFLOW.md）· `TLDR-MISSING`（没有 `## 0.` 块）· `TLDR-TOO-LONG`（块 >60 行）· `TLDR-INCOMPLETE`（缺 一句话/现在在哪/下一步/禁止/先读 任一标记）· `NO-STAMP`（第 2 行没有 `> 更新: YYYY-MM-DD`）· `STALE`（戳 >30 天）。
- `ok` 才把 `## 0.` 块当现状；`STALE` 或红码 = 先跑块里的核对命令再决定信不信，别直接引用块里的数字。
- `--audit` 末行 `projects=N · merge_now=N · takeover_defect=N · no_ledger=N`：`no_ledger` = 连台账都没有的项目数；这两个数就是这套机制的体温计，每周看一次。

## 防退化（三道锁，缺一道就会退化）

1. 派发侧：brief 的 `DONE WHEN` 要含「`SESSIONS.md` 有一块」，没有就补。
2. 收口侧：板行 `close --verify` 写 `SESSIONS.md:<anchor>`（锚 = 脚本打印的 `sess:<sha10>`）；写不出来 = 没写台账。
3. 探测侧：`--audit` 定期跑；`no_ledger` / `takeover_defect` 不下降说明没人写。

删条: 当 `merge_sessions.py --audit` 在全部项目上 `no_ledger=0` 且 `takeover_defect=0`，且 `append_session.py` 已成为 brief 默认收工步骤满 90 天 —— 本页降级为 `library/README.md` 索引里的一行，正文删除。

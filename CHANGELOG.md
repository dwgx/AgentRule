# 变更记录

> EN: Which rules each release added or retired.

这个文件记两件事：每一版发了什么；规则怎么退役。每条规则自带一行 `删条: <什么条件下可以删>`，退役时在当版留一行记录——只加不删是慢性失败，静默删行会让计数分叉。

## 未发布 — 2026-11-05

- **脱敏门不再打印被扫内容，且不完整扫描不给 PASS**（`scripts/check-leaks.sh`）。明细从「命中行原文（截 200 字符）」改成 `文件:行号 [类别]` —— 门自己不再把要找的密钥打到终端上。没有 `leaks.local` 又没给 `--no-local` 时退 **2**（旧的 `# WARN` + `TOTAL: 0` 会被当成通过）；`grep` 出错、0 个文本文件同样退 2。规则条数不变：base 12 + local 29。
- **安装器改成 allowlist**（`install/scope.txt` + `install/install.*` + `install/verify.*` + `scripts/gen-scope.py`）。只复制清单里列出的文件；清单缺失 / 为空 / 条目非法 / 条目指向不存在的文件时退 **4**，一个文件都不写，不退回「整棵树都装」。清单由 `scripts/gen-scope.py --write` 生成、`--check` 校验（CI 与 `assemble.sh` 都跑）。新增回归 `gates/scope_test.py`：造一棵含私人文件的源树，跑两个安装器，逐文件比对目标与清单，并验证四条失败路径都退 4 且不落盘。

## 0.1.0 — 2026-11-02

首次发布。四个平面（`install/` · `protocol/` · `adapters/` · `library/`），外加人读的文档、样例和脱敏门：

- `install/`：入口四步（`BOOTSTRAP.md` → `ASK.md` → `INSTALL.md` → `verify.ps1` / `verify.sh`）；部署状态机 `PROTOCOL.md`（协议标识 `ADP-1`）；`UNINSTALL.md`、`UPGRADE.md`；两个安装脚本。
- `protocol/`：六篇运行时规则——地板、状态、派发、门、恢复、记忆；页级账本 `manifest.tsv`（id / 修订号 / 字节 / 行数 / 依赖 / 摘要）。
- `adapters/`：omp、Codex、Claude Code 各一篇，加一篇选择表。
- `library/`：原规则书按「什么时候会去翻」分五个书架（floor / dispatch / recovery / tooling / specialist）。
- `docs/`：中文教程、真实案例、已知缺口。
- `examples/`：`machine.md`（本机笔记该记什么）、`brief.md`（一份填好的派发 brief）。
- `scripts/`：脱敏门 `check-leaks.sh`；上下文预算 `budget.py`（量入口与协议页塞进 `AGENTS.md` 要多少字节，对照 Codex 的 32,768 B 静默截断上限；协议页清单读 `protocol/manifest.tsv`）；协议账本校验 `check-protocol.py`（字节 / 行数 / `> EN:` / source 指纹 / 链接 / 400 行预算，红了退 1）。派发看板 `board.py` 与 brief 检查器 `briefcheck.py` 是**参考实现，不在本仓库**；判据以 `protocol/02-dispatch.md` 为准。
- `gates/`：`recursive-delete`、`unexpanded-temp-var`、`ai-attribution` 三道门的参考判据（`reference.py`）+ 20 条夹具（`fixtures.tsv`）+ 跑分脚本（`run.py`）。`--mutate` 故意改坏一条判据，夹具必须红并退 `1`；抓不到退 `3`。证明的是判据可复跑且能红，不是「安全」。

### 不含

- **门（hook）的执行层代码。** 门的实现绑死每套 harness 的接口，发一份通用的等于发一个跑不起来的空壳。本版给判据、最小伪码（`protocol/03-gates.md`）和三道门的可复跑参考判据（`gates/`），但不给调用点、不给退出码、不装 hook；逐家差异在 `adapters/`。
- **自动更新。** 没有更新逻辑，只有 `install/verify.*`。升级是手动 `git pull` 后重跑验收。
- **安全承诺。** 见 `SECURITY.md`。

### 来源与脱敏

规则来自一台 Windows 工作站上约两年的实战，每条挂着它换来的事故（`docs/case-studies.md`）。路径、主机名、盘符、账号已换成占位符，对照表在 `library/README.md`。

**以后怎么写。** 版本号 `MAJOR.MINOR.PATCH`：删掉或改写一条**已发布的判据** = MAJOR；新增判据 = MINOR；措辞、链接、错字 = PATCH。新增规则必须带 `删条:`；退役时在当版写一行 `删除：<规则> —— <删条成立的理由>`，不静默删行。每条记录带日期；数字带分母和同一次统计的范围。

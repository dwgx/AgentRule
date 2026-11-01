[中文](README.md) · [English](README.en.md)

# AgentRule

> EN: What an AI agent must never do, how work is handed off and accepted, and how a session resumes after compaction.

一套写给 AI agent 的规则书：哪些动作绝对不能做、活怎么交给另一个 agent 并验收、上下文被压缩或重启之后怎么接上。**每条规则后面挂着它换来的那次事故。**

[![version](https://img.shields.io/badge/version-0.1.0-blue)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT%20%2B%20CC--BY--SA--4.0-green)](LICENSE)
[![harness](https://img.shields.io/badge/harness-omp%20%7C%20Codex%20%7C%20Claude%20Code-lightgrey)](adapters/README.md)

> 73 个文件 · 53 篇文档 · 9,400 行 · 7 篇 [protocol](protocol/README.md) · 17 篇 [library](library/README.md) · 5 篇 [adapters](adapters/README.md) · 10 个 [install](install/INSTALL.md)

**一条规则长这样**（[`protocol/00-floor.md`](protocol/00-floor.md)）：

> **删除先算代价。** 临时目录之外不做递归强删；删含链接点（junction / reparse point）的树逐条删；
> 删源之前先记副本位置和 sha256；清回收站单独报备。

**装完长这样**（真跑一次 [`install/verify.sh`](install/verify.sh) 的输出）：

```text
PASS  docs                     54 files in <target>/.omp/agent/AgentRule
PASS  files                    54/54 个源文件都在且非空
PASS  empty                    0 个 0 字节文件（检查了 54 个）
PASS  entry                    790 bytes / 12 lines，入口块在（agentrule:entry）
PASS  load                     RULES.md 缺失，但 AGENTS.md 入口块在
N/A   hooks                    没有 hooks 目录（未安装 hook，无检查项）
PASS  totals                   lines 11710/11710 (+0.0%)  bytes 673244/673244 (+0.0%)

[summary] PASS 6  FAIL 0  SKIP 0  N/A 1
VERDICT: PASS (exit 0) — 全部检查通过
```

**这套规则改变了什么？** 30 次 A/B 会话的逐次记录、判据和五条 caveat 在 [`docs/evidence/behavior-ab.md`](docs/evidence/behavior-ab.md)：按预注册判据违规 10/15 → 2/15；但 t1 的差混了判据口径，t3 是零结果，干净的只有 t2。

**门能拦住什么**（真跑一次 [`gates/run.py`](gates/run.py) 的输出）：

```text
$ python gates/run.py
[fixtures] 20 rows / 3 gates: ai-attribution, recursive-delete, unexpanded-temp-var
PASS  rd-01   recursive-delete     expect=ALLOW  got=ALLOW
PASS  rd-02   recursive-delete     expect=DENY   got=DENY
PASS  rd-03   recursive-delete     expect=DENY   got=DENY
PASS  rd-04   recursive-delete     expect=DENY   got=DENY
PASS  rd-05   recursive-delete     expect=DENY   got=DENY
PASS  rd-06   recursive-delete     expect=DENY   got=DENY
PASS  rd-07   recursive-delete     expect=ALLOW  got=ALLOW
PASS  rd-08   recursive-delete     expect=DENY   got=DENY
PASS  rd-09   recursive-delete     expect=DENY   got=DENY
PASS  ut-01   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-02   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-03   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-04   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-05   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-06   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ai-01   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-02   ai-attribution       expect=DENY   got=DENY
PASS  ai-03   ai-attribution       expect=DENY   got=DENY
PASS  ai-04   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-05   ai-attribution       expect=ALLOW  got=ALLOW
[summary] match 20/20
[verdict] 夹具与判据一致 (exit 0)
```

同一套夹具，**故意把一道门的判据改坏一条**（`--mutate`，只贴 `FAIL` 行和末两行）：

```text
$ python gates/run.py --mutate
[mutate] recursive-delete: is_under_temp() 恒真：所有删除目标都当成在 temp 里
FAIL  rd-02   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 典型命中：temp 之外的递归强删
FAIL  rd-03   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 边界：先归一化再比前缀，"/tmp/.." 不是字符串前缀匹配
FAIL  rd-05   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：PowerShell 别名 + -Recurse -Force
FAIL  rd-06   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：脚本体里的 shutil.rmtree，命令词是 python
FAIL  rd-08   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 混合目标：一个目标在 temp 内不算数，逐目标判
FAIL  rd-09   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：cmd.exe 的 rd /s /q
[summary] match 14/20
[verdict] 变异被抓到：6 条 FAIL (exit 1)
```

**跑不红的门是假门。** 20 条夹具、3 道门的纯函数判据、10 条「换个读法就改判」的边界行，都在 [`gates/README.md`](gates/README.md) —— 包括**这套夹具不证明什么**（它不证明你机器上装了门，也不证明绕不过）。

**这套规则书塞进上下文要多少字节？**

```text
$ python scripts/budget.py
入口（每次会话都读）     AGENTS.md   2,599 B
协议（声明「必须遵守」）  protocol/   22,383 B
合计   : 24,982 B / 32,768 B  (76.2%)
余量   : 7,786 B
```

**76.2% 不是装饰**：Codex 的 `project_doc_max_bytes` 默认 32,768，超了**静默截断**，尾部直接消失且不报错。剩下的 7,786 B **大概还够一章，不够两章** —— 而且这是只装中文版的数；中英都装是 87.7%。这就是为什么入口只放指针、规则留在分篇按需读。

> 上面是 **Windows（CRLF）** 检出的字节。GitHub 上存的是 LF（`.gitattributes` 规定 `*.md text eol=lf`），同样的内容少 162 B。**两个数都对，看你从哪检出。** 自己跑一次 [`scripts/budget.py`](scripts/budget.py) 拿你那份的数。

## 给谁用

| 你是 | 你得到 | 从哪进 |
|---|---|---|
| 用 omp / Codex / Claude Code 的人 | 装好的规则书 + 两条验收命令 | [`install/BOOTSTRAP.md`](install/BOOTSTRAP.md) |
| 自己给 agent 写规则的人 | 原稿 + 事故档案，按需打开 | [`library/README.md`](library/README.md) |
| 想加机器门的人 | 判据与最小伪码，不含实现 | [`protocol/03-gates.md`](protocol/03-gates.md) |
| 只是好奇 | 60 秒零安装版 | [`docs/60s.md`](docs/60s.md) |

## 怎么开始

```bash
git clone https://github.com/dwgx/AgentRule.git
cd AgentRule
bash install/install.sh --dry-run     # 先看计划，不写任何东西
bash install/install.sh               # 真装（自动探测 harness 和源目录）
bash install/verify.sh                # 验收，要看到 VERDICT: PASS
```

Windows 用 `powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1`，参数相同。

**全程 3–5 秒，零提问。** 脚本自己探测你装的是哪套 harness、装在哪。探不到才停下来问。

**不想让脚本动手**：把整个文件夹交给你的 agent，让它读 [`install/BOOTSTRAP.md`](install/BOOTSTRAP.md)。这条路会问你 9 个问题（清单在 [`install/ASK.md`](install/ASK.md)），15–30 分钟，但你能逐条确认它要改什么。

## 和别的东西有什么不同

| | 是什么 | 管什么 | 不管什么 |
|---|---|---|---|
| `AGENTS.md` | 单文件项目约定 | 本项目的写法 | 跨会话流程、派发、验收 |
| prompt 合集 | 提示词片段 | 一次对话 | 安装、回滚、升级 |
| hook 框架 | 强制拦截 | 能机器判的动作 | 判断类规则、上下文恢复 |
| **AgentRule** | 规则书 + 部署协议 | 流程、派发、恢复、验收 | 不提供门代码（见 [SECURITY.md](SECURITY.md)） |

## 它不做什么

- **不保证安全。** 这是指导（guidance），不是强制（enforcement）。**这里没有任何安全边界**：不防提示注入、不防恶意 skill 或 MCP server、不防你自己手滑。详见 [SECURITY.md](SECURITY.md)。
- **不自动更新。** 仓库没有更新逻辑。升级 = 手动 `git pull` 后重跑验收；不重跑就不知道装的是哪一版。见 [`install/UPGRADE.md`](install/UPGRADE.md)。
- **不替你装门。** 默认只装规则文本。hook 是每套 harness 自己的机制，本仓库只给判据（[`protocol/03-gates.md`](protocol/03-gates.md)），门要你自己实现。
- **不保证 agent 不犯错。** 它减少的是同一个错反复犯，不是消灭错误。
- **不改你的代码、不换你的模型。** 安装只写 harness 配置目录和状态目录，不碰项目。
- **不替你选。** 装哪套、用户级还是项目级、覆盖还是追加，由你答；猜错的后果写在 [`install/ASK.md`](install/ASK.md) 每个问题后面。

## 仓库长什么样

一个文件只属于一个平面：

- [`install/`](install/INSTALL.md) — 入口。agent 从这里进，四步走完
- [`protocol/`](protocol/README.md) — 换 harness 也不变的规则（7 篇，合计 ≤400 行）
- [`adapters/`](adapters/README.md) — omp / Codex / Claude Code 三家的差异
- [`library/`](library/README.md) — 原稿与事故档案，按需打开，不要预载
- [`docs/`](docs/tutorial-zh.md) — 人读的教程、案例、已知缺口
- [`examples/`](examples/brief.md) — 两份填好的样例
- [`gates/`](gates/README.md) — 20 条门夹具 + 3 道门的参考判据，跑一次看门怎么红

## 脱敏

原稿来自一台真实的 Windows 工作站。路径、主机名、盘符、账号已换成占位符，对照表在 [`library/README.md`](library/README.md)。

发布前的脱敏门是 [`scripts/check-leaks.sh`](scripts/check-leaks.sh)。**它只带 12 条通用规则**；用户名、盘符、私有仓名这 5 类要自己写 `leaks.local` 再用 `--local` 指过去，否则开头会打 `# WARN`，那个 `TOTAL: 0` 不算数。干净时末行 `TOTAL: 0`、退出码 0。

## 状态

**v0.1.0 · 2026-11-02 首次发布 · 单人维护 · issue 不保证响应。**

已知缺口清单在 [`docs/known-gaps.md`](docs/known-gaps.md)（15 条，含「三家 harness 都没有端到端验收」）。改动记录在 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

- 代码（`install/*.ps1`、`install/*.sh`、`scripts/*`）：**MIT**，见 [LICENSE](LICENSE)。
- 文档（全部 `*.md`）：**CC BY-SA 4.0**，见 [LICENSE-docs](LICENSE-docs)。注意带 ShareAlike —— 你改写后发布的版本也必须用同一许可。

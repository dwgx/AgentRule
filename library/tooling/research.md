<!-- source: AgentRule/研究.md @ 843b48ea -->
# 研究
> EN: Research is not chatting: fix the question, check local sources first, tie every claim to a source or a command, ship a check instead of an essay.
<!-- summary: 研究怎么跑：先定问题、先查本地、每条结论追到来源或命令。 -->

> 伴生工具：本页提到的 `<sessq>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

一句话：研究不是聊天——先定问题、先查本地，每条结论追到来源或命令；学到的落成 skill / 检查 / 一条命令，不落成长文。

## 三种活，三把工具

| 你手上是什么 | 用什么 | 产出（默认 `~/.owner/ops/research/<slug>/`） |
|---|---|---|
| 一个问题，要一份可核报告（选型 / 尽调 / 证据复核 / 文献扫描） | skill **`deepresearch`** | `BRIEF.md` · `sources.tsv` · `claims.tsv` · `REPORT.md` · `LEDGER.md` |
| 一个可测指标，要一轮一改（性能 / 覆盖率 / 测试数 / loss） | skill **`autoresearch`** | `autoresearch.json` · `results.tsv` · `autoresearch/<tag>` 分支 |
| 一个目标，要连续多轮、多研究员、可恢复（代码考古 / 大范围综述 / researchd 作业） | skill **`auto-deepresearch`** | `QUESTION-TREE.md` · `MASTER-INDEX.md` · `SYNTHESIS.md` · `OPEN-QUESTIONS.md` · `LEDGER.md` · `checkpoints/` |
| 先不确定用哪个引擎 | skill **`research-router`** | 25 行路由表，读它先选型 |
| 多个目标要排队跑（按需后台） | `researchd` | `queue.jsonl` · `jobs/<id>/` |

选型一句话：**先不确定 → `research-router`；一个问题 → `deepresearch`；一个指标 → `autoresearch`；一个目标树 → `auto-deepresearch`；只查事实 → `intel-lookup` / `sessq`（`sessq` 不在本仓库，见页首「伴生工具」），不立项。**

不要用重型流水线做一句话能答的事；也不要把该核的结论拿记忆顶。

## 通用铁律（三种模式共用）

1. **先本地后联网。** `intel-lookup` → `sessq`（历史会话）→ 项目文档 / `git log` / `git status` → 官方文档 / 仓库 → 网页搜索。每个查询、命中数、有用 source id 记进 `LEDGER.md`。
2. **无来源，不成条。** `claims.tsv` 每行至少一个 `source_id`；没有就写 `[INFERENCE]` / `[UNKNOWN]`，不许写成事实。
3. **无执行，不算过。** 测试 / 门只认命令、cwd、退出码、字面成功标记；文档里的「已通过」不算，agent 说「跑过了」不算。
4. **数字带日期和分母。** 写 `4.2% (S1, 2024-03-31)`，不写裸 `4.2%`；引用前重算。
5. **一手优先。** 官方文档 / 源码 / 原始数据 / 现场命令 > 二手转述；二手只用来找一手。
6. **矛盾保留。** 两个来源冲突就都记，标 `contradicted`，不取平均、不挑顺手的；解决不了就写进 open questions。
7. **研究可以充分，写入只满足点名；研究只读项目树。** 产出只写 `~/.owner/ops/research/<goal-slug>/`（researchd 另有 job dir）；要改项目就交回产品线，不在研究里顺手改。
8. **不读整份 transcript。** 用 `sessq` 找、`sessread` 读窗口；引用带时间戳。
9. **无凭据。** token / 密码 / cookie / 私钥 / 个人数据不进任何研究文件；笔记里也脱敏。
10. **停要有名。** 每个停都写进 `LEDGER.md` 和 `SYNTHESIS.md`：`STOP-COMPLETE` / `STOP-EVIDENCE` / `STOP-REPEAT` / `STOP-ERROR` / `STOP-BUDGET` / `STOP-PROJECT`；不静默停。

## 三种模式的最小契约

### `deepresearch` — 一个问题，一份可核报告

- 八个阶段（Phase 0–7）：Frame → Index → Query expansion → Read primary → Claim ledger → Gap loop → Synthesis → Independent verification。
- `BRIEF.md` 的 **DONE WHEN** 必须是一条可证伪句；`sources.tsv` 每源有 locator + date + quote；`claims.tsv` 每行 A/B/C 分级。
- 报告首行先答；synthesis 不许引入 `claims.tsv` 没有的 claim；中心 claim 交 `verifier` 独立复核，未核标 `[UNVERIFIED]`。
- 停：连续 2 个空轮或预算耗尽。细则 = skill `deepresearch` 的 `SKILL.md`；状态 helper 在 skill 自带的 `scripts/deepresearch_state.py`。

### `autoresearch` — 一个指标，一次一个假设

- `autoresearch.json` 只允许一个 `mutable_scope`；一轮 = 一个假设 = 一个 commit，先 commit 再测。
- `results.tsv` 只追加 baseline / keep / discard / crash；discard / crash 回 best commit；超时 = crash。
- 不许改测试 / benchmark / metric parser / stop policy 让数字好看，不许装依赖。
- 停：`max_iterations` / `max_no_improve` / `target_metric` / `fixed_budget_sec`。细则 = skill `autoresearch` 的 `SKILL.md`；脚本在 skill 自带的 `scripts/autoresearch_loop.py`。

### `auto-deepresearch` — 一个目标，一棵问题树

- `QUESTION-TREE.md`：root = 目标原话；子问题原子、可答、能改变具体决定；frontier = 无未解决依赖的 open 问题。
- 每个 frontier 问题一个 `researcher`（默认并发 3，硬上限 8），每人只写 `research/Q<N>/{REPORT.md,sources.tsv,claims.tsv}`。
- 每轮合并 `MASTER-INDEX.md`，记 `C-*` 矛盾 / `G-*` 缺口 / `R-*` 重复，先写 checkpoint 再派下一轮。
- 停：`STOP-COMPLETE` / `STOP-EVIDENCE`（2 轮零新证据）/ `STOP-REPEAT`（同结论 3 次）/ `STOP-ERROR` / `STOP-BUDGET` / `STOP-PROJECT`。
- 压缩 / 重启按 `LEDGER.md` → 最高 checkpoint → `QUESTION-TREE.md` → `MASTER-INDEX.md` 恢复；项目适配器 `~/.owner/ops/researchd/adapters/<project>.md`，无适配器写 `ADAPTER-MISSING`。细则 = skill `auto-deepresearch` 的 `SKILL.md`。

### `researchd` — 按需研究队列

- 前台服务（不装 Windows 服务、不建后台守护）：`start` 跑队列，`stop` 写停止哨兵，`status` / `enqueue` / `tail` 查。
- 队列在 `queue.jsonl` + `state.json`；job 在 `jobs/<id>/`。收尾要求 `SYNTHESIS.md` / `OPEN-QUESTIONS.md` / `LEDGER.md` 非空；`STOP-ERROR` 才非零。
- 入口：`~/.owner/ops/researchd/researchd.py`（`--help` 查命令）。

## 论坛采集（linux.do / linux.sb）

> 2026-10-18 实测 + `ForumMethodVerifier` 复核；完整证据：`~/.owner/ops/research/linux-do-sb-research-methods/REPORT.md`。只读；不自动发帖。

| 目标 | 路径 | 实测 / 边界 |
|---|---|---|
| linux.do 主题/评论 | `r.jina.ai` 代理 Discourse JSON：`/t/topic/<id>.json`，`?page=N` 翻页 | 200；`posts_count` + 20 条/页；翻到 `ceil(posts_count/20)` |
| linux.do 列表/用户 | `/latest.json`；`/u/<name>.json`；`/sitemap_1.xml` | 30 主题 + `more_topics_url`；用户对象；单分片 10k URL |
| linux.do 页面 | 真实 Chromium（browser 工具） | 过 Cloudflare；滚动懒加载；只读 |
| linux.sb 主题 | 直接 HTML | 200；首帖 + JSON-LD；评论登录墙 `共有 N 条评论，登录后可见` |
| linux.sb 批量 | `/sitemap.xml`；`/forum/<id>?sort=comment&p=N` | 16,459 主题 URL；9 个公开版块约 338 页；分页是 `sort=comment&p=` |
| linux.sb 用户 | `/user/<uid>` | 200；昵称/UID/积分/tabs |

```bash
# linux.do 主题 JSON（公开，经代理）
curl -sS 'https://r.jina.ai/https://linux.do/t/topic/2773426.json' \
  | python -c "import sys,json; s=sys.stdin.read(); d=json.loads(s.split('Markdown Content:',1)[1]); print(d['posts_count'], len(d['post_stream']['posts']))"
# linux.sb 主题 / 索引 / 版块分页
curl -sS -A 'Mozilla/5.0' 'https://linux.sb/topic/13939' -o topic.html
curl -sS -A 'Mozilla/5.0' 'https://linux.sb/sitemap.xml' -o sitemap.xml
curl -sS -A 'Mozilla/5.0' 'https://linux.sb/forum/1?sort=comment&p=2' -o forum-p2.html
```

- **裸 HTTP 不行**：linux.do 直连 403 `Cf-Mitigated: challenge`；`/search` 代理返回 CAPTCHA，且 robots `Disallow: /search`，不要抓。
- **linux.sb 没有公开 JSON API**：`/topic/<id>.json`、`/api/*` 404；`/search` 登录墙；登录带 CSRF + CAP，**不自动登录**，评论只在 Owner 授权会话读。
- **失败路径**：Common Crawl 504；Wayback 的 linux.do 主题多为 403；`web_search` provider 429 / bot challenge。
- **合规**：linux.do guidelines 禁止 AI 生成内容与自动发帖；linux.sb robots 允许主题/版块页。只读、限速、缓存、按 topic id 去重；不存 cookie/token。
- **删条**：两个论坛改版、代理失效或 Owner 取消论坛研究 → 删本节。

## 学习怎么沉淀（迭代）

- **研究笔记不是规则。** 结论先落 workspace 和报告；要进 `library/` 只走四触发：同一个错第二遍 / review 审计抓到 / 同一句纠正重复出现 / 新同事上下文（`library/README.md`）。
- **能落成机器门就别写散文。** 一个错第二次出现 = 升级成检查（hook / gate / briefcheck），不是再加一行字。
- **把一次研究收成可复用的形状**：一条命令、一个脚本、一个 skill 或一页指针；不要把长报告抄进常驻上下文。
- **普通学习随意联网，不用先问**；查本机事实先用 `intel-lookup`，别重新推导（`library/recovery/work.md`「学」）。

## 边界

| 要干什么 | 去哪 |
|---|---|
| 查这台机器的事实（版本 / 装没装 / 历史测量） | `intel-lookup`（`library/tooling/tools.md`） |
| 查历史会话 / 读某条会话 | `library/tooling/archaeology.md`（`sessq` / `sessread`） |
| 写 / 改 agent 消费的文档 | `library/dispatch/writing-for-agents.md` |
| 派工 / 子代理 / 板 | `library/dispatch/dispatch.md`（§协作 / §多路派发） |
| 收工 / 复盘 | `library/recovery/work.md` · `library/recovery/retro.md` |

**删条: 三种研究 skill 退役或合并，或 Owner 取消研究 / 学习迭代要求 → 删本页并回滚 README / skills / RULES 的接线。**

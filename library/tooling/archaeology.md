<!-- source: AgentRule/考古.md @ 54d917a6 -->
# 考古会话
> EN: Reading past sessions: use the session index with a budget — never read a whole transcript or grep raw jsonl.
<!-- summary: 查旧会话时怎么用索引加预算，不整份读 transcript、不 grep 原始 jsonl。 -->

> 伴生工具：本页提到的 `<sessq, sessread>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

各家的会话都在同一份索引里（Grok 独立，但历史仍可读）。**禁止**整份读 jsonl / grep transcript。
一条 `sessq q` 大约 200 token；生翻一份会话是几万 token（`sessq` / `sessread` 不在本仓库，见页首「伴生工具」）。

索引：`sessq stats` 打印的那份，现在是 `~\.omp\extra-hands\CACHE\sessions-v2.sqlite`。条数以这次 `sessq stats` 为准，不要背旧数字。
Grok 旧索引已按 Owner 的要求抹掉。不要 `sessq build --full` 把旧 Grok 捞回来，除非他点名。

## 先看蒸馏（2026-10-15 起）

多数项目已有一份 `SESSION-DIGEST.md`（项目根；个别在 `ops/` 下，如 <project-c>——总表见 `ops/research-2026-10-15/DIGEST-INDEX.md`；会话蒸馏 = 时间线 / 决策 / 死胡同 / 会话索引）。**考古前先读它**——多数问题读它就能答；只有要挖细节才走下面的会话流程。

配套速查（2026-10-16 建）：会话考古检索 / 盲区 / 配方 / 项目还原一页查 = `~/.owner/ops/session-semantics-2026-10-16/SESSION-SEMANTICS.md` + 同目录 `SESSION-MAP.md`。

## 读某一条（有人点名）

Owner 丢来一条会话——id、`codex://threads/<uuid>`、或文件路径：

1. `sessread <那个东西>` —— 自己认家、直读原文件，不用索引。`--meta` 只看时间线，`--tail 5` 只看最后几轮，`--chars` / `--budget` 管字数。
2. 只记得关键词：`sessq q "<词>" --limit 3 --budget 2000` 先找，再 `sessread` 读。
3. 索引没收录（新会话）：`sessq build`（增量，几秒）再 `sessq show`。

各家文件在哪（sessread 会自己找，这张表是给你认路的）：

| 家 | 文件 |
|---|---|
| claude | `~\.claude\projects\<cwd 变体>\<uuid>.jsonl` |
| codex | `~\.codex\sessions\YYYY\MM\DD\rollout-*<uuid>.jsonl`；归档在 `~\.codex\archived_sessions\` |
| omp | `~\.omp\agent\sessions\<cwd 变体>\<时间>_<uuid>.jsonl` |
| grok | 已卸载，仅索引残留（`~\.grok` 不存在；历史 275 条会话仍在 `sessq` 索引里，原文件已不在原路径） |

`sessq build` 收四家；codex 两棵树都收（`~\.codex\sessions` + `~\.codex\archived_sessions`，2026-09-29 起）。没进索引的会话仍可用 sessread 直读，不等 build。

## 顺序（省 token）

1. `sessq latest` — 最近几条，认家。源文件已经不在的会话不会出现。
2. `sessq q "<词>" --limit 3 --budget 2000` — 先窄。可加 `--harness omp|claude|codex|grok`。
3. 命中后 `sessq show <家> <id前缀> --meta` — 只有时间线，没有正文。
4. 还要证据：`sessq show <家> <id前缀> --chars 800 --budget 4000`
5. 仍不够：再加关键词重搜，不要加 `--limit`、不要去掉 `--budget`。

`--meta` 只要标题/cwd/回合。`--budget` 是整段结果的字数帽，截断看得见。

## 搜哪一家

| 要找 | `--harness` |
|---|---|
| 自己刚才的活 | 当前这家，或先 `latest` |
| omp 长跑 / extra-hands | `omp` |
| Claude 实现 | `claude` |
| Codex 规格 / 派发 | `codex` |
| Grok Chrome / 学 | `grok` |

Owner 原话、派发 brief、失败原因：搜他的原句，不要搜模型自己的总结。

## 不要

- `Get-Content` / grep 一份 `*.jsonl`
- `sessq show` 不带 `--budget` 把 3 MB 会话灌进来
- 为了「再确认一眼」把同一 id 连 show 三次
- 文档里引用会话只写 13 位前缀：**必须写完整文件名或 ≥16 位前缀**（实测 5 对 13 位前缀撞车——`01a12bf4-0a4a`/`-0a53` 等；`SYNTH-02 §I10`）
- 索引没有就先 `sessq build`（增量很快）；Owner 删过会话才 `sessq build --full`
- 数 `mode_change` 事件当 goal 数：同 objective 每轮重写一次，100 事件 = 1 真目标也常见（实测虚高 233 倍）。数目标只认 `goal.id` / objective 全文哈希（见 `ops/research-2026-10-10/J-omp-goal.md:88`）。

## 索引的三个结构性盲区（2026-10-11 实测，ops/research-2026-10-11/M7-index-health.md）

```
① 子 agent transcript 从不在索引里 —— session_index_v2.py 的 glob 只到
   会话目录【深度 1】；子代理产物在 <会话目录>/<名字>.jsonl（深度 3）。
   实测：一场运维会话的 17 个 worker transcript 无一被索引。
   ⇒ 要找子代理说过什么，索引帮不上，去会话目录里直接列文件。

② 撞 600 闸的会话，头部【永久】不可检索 —— 【2026-10-12 修复后语义 = 保最新 600】
   索引保留每个会话的【最后】600 条（`session_index_v2.py` 的 `del msgs[0]`），更早的被丢。
   判据：索引里该会话 min(ts) 不在文件第一条消息上。
   ⇒ 读头部（更早的上下文）只能用 sessread（读原文件），或用 python 直接读 jsonl 头段。
   （2026-10-11 原文写「尾部不可检索」——那是修复前「保前 600」的语义，方向已反；
   修复记录见 `CHANGELOG.md` 2026-10-12 与 `library/floor/incidents.md` 第 11 个仪器。）

③ sessread 短 id 会按 mtime 误选 —— 同一前缀下子代理文件 mtime 更新，
   实测命中过 <project-d>DeepRead.jsonl 而不是主 transcript。
   ⇒ 先 --meta 确认是哪一份，或直接给全路径。
```

## 归档现状与还原（2026-10-16 修正）

- **归档库**：`<backup-root>/sessions-archive/` 下 130 个 `.jsonl.gz`，合计 **71,847,794 B**（2026-10-16 实测；2026-11-02 复核：`<backup-root>/sessions-archive/` 递归 130 个 `.jsonl.gz` / 71,847,794 B，与旧数逐字节一致；旧版写「`~/.owner/archive/` / 299,002,283 B」——位置与口径均已过时），`gzip -t` 全量校验 **bad=0**。
- **还原**：`python "~/.omp/extra-hands/CACHE/session_deep_archive.py" restore --manifest "~/.omp/extra-hands/CACHE/session-deep-archive-manifest.json" --id <session-id>`（按 id 还原单个会话；**不要**整库解压——71MB 解压后翻数倍；`gc.lock` 存在时 restore 拒绝运行）。
- **保留策略**：`.gz` 压缩件**不设过期**（2026-10-15 更正：此前本行写「保留 7 天 + 定时器清理」——实测**无该定时器**（schtasks 零命中），且与设计「`.gz` 永不删」矛盾；以本行为准）。要留的证据随时可取，`restore --id` 单件还原。
- **归档冻结截尾帧 → 判完成看产物**：归档件的末帧可能是冻结时刻的截尾帧（`pending/interrupted/unknown` 会被深归档门挡下）；判「这个会话做完了没有」看**产物**（报告/回执/文件在不在），不看转录末帧状态。
- **custom-session-files**：`~/.omp/agent/custom-session-files/` 存的是会话产物文件（非转录）；排查某会话产出先看这里与 `sessions/<slug>/<stem>/` 目录。
- **家族备份根（2026-10-16 起）**：历史会话副本统一归档在 `<backup-root>\`（结构/约定见其 `<backup-root>/README.md`；冷档镜像 `sessions-archive/` 进行中）。
- **<project-a> 实例（2026-10-16，2026-10-31 删除）**：原家族备份根下 `sessions\<project-a>` 子目录（raw-20261016 ×2827 件 + deepread ×5 + _SOURCE）已在一次删除窗口里删除，路径作废；隔离区 `quarantine/<project-a>/`（975 件，只进不删）与收据 `receipts/<project-a>-*` 的现状需重新核对。
- **codex 侧不是 bug**：codex 索引对 >600 条会话**流式直写**（边读边写索引），进度条看着「卡住」但实为直写路径；
  判据 = 索引文件在持续增长。别当成死循环杀。

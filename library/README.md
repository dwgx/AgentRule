<!-- source: AgentRule/README.md @ 88a04d09 -->
# 库层索引 / Library index
> EN: Which library page to open for what, and the placeholder table every page in this repo shares.

> 这一层是**来历与过程**：每条规则为什么存在、当时怎么栽的、原话是什么。
> 判据（什么必须成立、什么必须拒绝、首行长什么样）在 `protocol/`；本层**按需打开，不预载**。

## 怎么用

- **不要整目录预载**——本层近两千行，每轮都塞进上下文是净亏损。常驻只放铁律和入口。
- 先读 `library/floor/hard-floor.md` 与 `library/floor/incidents.md`，其余按任务取。
- 正文里的交叉引用都写成**从仓库根算的路径**（如 `library/dispatch/dispatch.md`）；旧中文文件名（`派发.md`、`卡.md` 等）只作历史说明出现，不再是链接目标。
- 一条规则只写一遍：判据在 `protocol/`，来历在这里，各家差异在 `adapters/`。

## 两个档位（W / S）

同一个模型强弱不同，读法不同：看本会话 system prompt 的 `Model:` 行——`deepseek-*` / `glm-*` 是 **W 档（弱档）**，`kimi-*` / `gpt-6-*` / `opus-*` 是 **S 档（强档）**。

- **W 档顺序**（照做，别靠自觉）：① 本页 ② `library/floor/incidents.md` §一（Owner 反复说的）③ `library/recovery/work.md` §做成 ④ `library/dispatch/dispatch.md` 的 brief 模板 ⑤ 干活前对一次本机陷阱（你的 `MACHINE.md`；样板见 `examples/machine.md`）⑥ **派活/交活前开 `library/dispatch/cards.md`，把对应卡粘进 brief 的 `# Change`**。
- **S 档顺序**：① 本页 ② 直接干。只在**踩到门**或**两种读法差很远**时再开库页；不要为了「保险」预读。
- **两档都不跳的**：门（hook / `board.py` 拦下来就得改）；`STATUS:` 首行；`DONE WHEN` 能跑一条命令。
- 依据：402 次真实门命中里，`recursive-delete` 21.2%、`powershell-dollar` 39.0% 的违规，模型在触发前的 thinking 里**已经点名了那条规则**。写在上下文里 ≠ 被执行。

## 五个书架（按「什么时候会去翻」分）

| 书架 | 什么时候翻 | 篇数 |
|---|---|---|
| `library/floor/` | 开工前 / 想改一条规则前 | 2 |
| `library/dispatch/` | 派活、交活、答 Owner | 4 |
| `library/recovery/` | 压缩后、重启后、一波收工后 | 3 |
| `library/tooling/` | 用工具、做研究、读旧会话 | 6 |
| `library/specialist/` | 只有接逆向站的人 | 2 |

## 文件地图

| 路径 | 原文件名（历史） | 内容 | 解决什么 |
|---|---|---|---|
| `library/README.md` | `README.md`（本页） | 索引、档位、占位符 | — |
| `library/floor/hard-floor.md` | `硬地板.md` | 44 条硬规矩与执行层标记 | 44 条硬规矩按执行层分级，告诉你哪条会被门拦住、哪条只是提示。 |
| `library/floor/incidents.md` | `翻车.md` | 真实事故档案，带原话与计数 | 本机真实事故档案，带原话与计数；引用任何数字前先来对号。 |
| `library/dispatch/dispatch.md` | `派发.md` | 派发协议：占坑、brief、门、收工 | 一次派活怎么占坑、写 brief、过检查、收工带证据，以及扇出与回执。 |
| `library/dispatch/reply-shape.md` | `回答形状.md` | 对 Owner 怎么答、英文怎么进中文 | 答 Owner 的形状：结论先行、最多五条、无客套，附英译中纪律。 |
| `library/dispatch/writing-for-agents.md` | `写给agent.md` | 写 agent 消费文档的判准 | 写任何 agent 要读的文档前的判准与反例：指针、上下文成本、删减、完成条件。 |
| `library/dispatch/cards.md` | `卡.md` | 弱档执行卡十张（W 档用） | 弱档派活时把洞察换成必填字段和必跑命令，粘进 brief 的 `# Change`。 |
| `library/recovery/recovery.md` | `恢复.md` | 压缩 / 重启后接上 | 压缩、重启或新窗口后，怎么找到板、核对磁盘、按五段模板交出去。 |
| `library/recovery/work.md` | `干活.md` | 干活八原则 | 非琐碎活的八条原则：可跑的完成条件、有限自主、最小写入、证据先行。 |
| `library/recovery/retro.md` | `覆盤.md` | 一波收工后的复盘 | 一波收工后怎么从四个抽屉收候选，过四道触发才准进规则本。 |
| `library/tooling/tools.md` | `工具.md` | 已装工具与用法、MCP 政策、编码检查 | 本机装了哪些工具、怎么用、MCP 与编码检查的政策边界。 |
| `library/tooling/browser.md` | `浏览器.md` | 浏览器规则 | 用 agent 浏览器干活：自己开页面、一任务一页、用完关掉自己开的页。 |
| `library/tooling/research.md` | `研究.md` | 研究怎么跑 | 研究怎么跑：先定问题、先查本地、每条结论追到来源或命令。 |
| `library/tooling/archaeology.md` | `考古.md` | 读历史会话 | 查旧会话时怎么用索引加预算，不整份读 transcript、不 grep 原始 jsonl。 |
| `library/tooling/skills.md` | `skills.md` | 什么时候该有 skill、主线流图 | 什么时候该有 skill、下一步接哪一步；具体名字以本机目录为准。 |
| `library/tooling/knowledge.md` | `知识.md` | 项目知识台账：收工写一块、到阈值合并 | 每个项目维护一份知识台账，收工追加七段一块，到阈值再合并。 |
| `library/specialist/README.md` | `specialist/README.md` | 扩展线索引 | 逆向线入口：谁能读、和通用库怎么分工、开工先读哪页。 |
| `library/specialist/reverse-station.md` | `specialist/逆向站.md` | 逆向站：红线与接线 | 反编译、解包、调试必须走的站：读序、单会话接线与红线。 |

「解决什么」一列逐字抄自各页页首的 `<!-- summary: … -->` 注释；改一页先改注释，再同步这一列。

## 占位符对照

本仓库所有页共用这一套。看到尖括号就换成你自己的值，不要照抄。

| 占位符 | 原文 |
|---|---|
| `~` | 用户家目录（`%USERPROFILE%`） |
| `~/.owner/` | 该账号的配置与运维目录（原以账号短名命名） |
| `<project>` / `<project-2>` | 两个产品树根 |
| `<tools>` | 工具与逆向站所在的目录 |
| `<reports-dir>` | 报告与审计产物根 |
| `<backup-root>` / `<backups>` | 备份与冷档根 |
| `<vault>` | 凭据库目录 |
| `<repo>` | `<project>` 下的一个代码仓 |
| `<profile>` | 一个 harness profile 名 |
| `<provider>` | 一个模型服务提供方 |
| `<project-a>` … `<project-j>`、`<service-a>`、`<program-a>`、`<farm-a>`、`<device-project>`、`<lane-a>`、`<ops-vault>` | 项目 / 服务 / 悬赏项目 / 采集线 / 设备项目 / 工作线 / 运维库的代号（一律换成角色名） |
| `192.0.2.x` | 内网地址（TEST-NET-1 保留段） |
| `build-host` / `remote-vps` / `mac-box` | 三台远端机器 |
| `example.invalid` | 任意域名 |

## 注意

1. 这套规则写于**一台具体的 Windows 工作站**：路径、主机名、服务名、盘符都是那台机器的，换机器不能照抄。样板见 `examples/machine.md`。
2. 使用前先把路径和主机名换成你自己的；本仓库已脱敏，占位符见上表。
3. **这里没有任何安全边界**：它是给人读的指导（guidance），不是强制执行（enforcement）；真正拦人的是各 harness 自己的 hook 与门。
4. 本层提到的 `guards.ts` / `gatecheck` / `run_all_gates.py` / `omp_dispatch.py` / `hook_probe.py` / `sessq` / `sessread` / `append_session.py` / `merge_sessions.py` **不在本仓库**——每页页首的「伴生工具」行会点名，正文只给格式与判据，不是可直接跑的命令。

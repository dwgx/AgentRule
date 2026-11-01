<!-- source: ops/oss/08-REPO-TREE.md §5 · 派生自 library/dispatch/dispatch.md -->
# 派发
> EN: How work is reserved, briefed, dispatched, and accepted with proof.

派发是五个动作，缺一个都不算派出去：**开卡 → 写 brief → 过检查 → 派 → 收卡**。**父代** = 派活的会话，**工人** = 接活的会话（看不到父代的历史）。
参考实现**不在本仓库**：`board.py`（开卡与收卡）与 `briefcheck.py`（brief 判据）是这套协议的原始实现，你要自己写一份等价的。下面给的是**命令形状与判据**，不是可直接跑的命令。
为什么这么切、踩过什么，见 [`library/dispatch/dispatch.md`](../library/dispatch/dispatch.md)；本页只写判据。

## 1. 开卡：四参数

```bash
python scripts/board.py open --id <ID> --worker <名字> --scope "<绝对写路径>" --done "<一条命令或一个文件>"
```

| 参数 | 判据 |
|---|---|
| `--id` | 本次唯一；重开换新 ID，不改历史行 |
| `--worker` | 收工时对得上同一个名字 |
| `--scope` | **只收绝对路径**；列到你要写的那一层，列父目录会连带占住子目录 |
| `--done` | 不许自指（写成对账条件，那行永远关不掉）；写成一条命令或一个文件 |

- 撞上别人已占的路径 → 工具拒，别绕。比较前折叠 `.`/`..`、忽略大小写、认 `D:/x` 与 `/d/x` 两种写法。
- 只读派发用 `--read-only`：不占写路径、不与人冲突，但仍然记账。
- 看板**只追加，永不改写**。测板时把 `BOARD_FILE` 指向临时文件，别往真板里塞探针行。

## 2. 写 brief：两段必含

brief 开头逐字一行 `YOU ARE THE WORKER.`，下一行 `board: <ID>`。两段缺一不可：

| 段 | 判据 |
|---|---|
| `# Non-Conflict` | **只列写路径**，逐条，与 `--scope` 同集合；读到哪里都行，不用列 |
| `# Acceptance` 里的 `DONE WHEN:` | 第三方能跑的一条命令，或一个能看的文件。形容词不算；cwd、套件名、期望退出码、断言数写全 |

其余按需：`# Target`（路径写死，不写「相关目录」）· `# Needs`（write / bash / read-only）· `# Change`（允许改什么、禁止改什么）· `# Report`（**绝对路径**，父代读得到）。

- **brief 自足**：工人看不到你的上下文，也看不到别人的 brief。写「同上」= 没写。
- 附加材料用**指针**：给路径 + 要读哪一段，不把上游正文抄进 brief。弱档模型派活前把对应卡粘进 brief（[`library/dispatch/cards.md`](../library/dispatch/cards.md)）。
- 填完真值再跑 `python scripts/briefcheck.py <brief>`；**退出码非 0 就别派**。
- 模板原样复制会被拒（`Non-Conflict` / `DONE WHEN` / `Report` / `Needs` 四项）——这是设计意图：尖括号必须换成真值。

## 3. 派

- 同一进程：用本家 harness 的 subagents，一个切片一个名字；名字就是回执地址。
- 跨进程 / 换 harness：用你自己的派发入口；这一层本仓库不附，见 [`adapters/README.md`](../adapters/README.md)。
- 派之前对齐 `--scope` 与 `# Non-Conflict`；不一致就重写，别指望工人自己收窄。

## 4. 收卡：ok 要证据，其余三态要理由

```bash
python scripts/board.py close --id <ID> --verdict ok --verify "<父代真跑过的命令或真查过的文件>"
```

| `--verdict` | 必带 | 判据 |
|---|---|---|
| `ok` | `--verify` | 写文件路径时工具真去查它在不在；写命令时工具**不核**你跑没跑过，只记下来——这一格靠你 |
| `failed` | `--result` | 为什么失败 |
| `blocked` | `--result` | 卡在哪个外部条件 |
| `abandoned` | `--result` | 去哪了 / 被谁接了 / 为什么弃 |

- 同一 ID 只能 close 一次；没跑过就写 `failed`，不拿 `ok` 遮。
- **以父代复跑为准**：工人自述与复跑不一致时，信复跑。
- 收一个 close 一个，别攒到最后——攒着就会出现「派了六个，两个没回，忘了」。

## 5. 首行制

工人的最终答复**第一行只准** `STATUS: DONE` 或 `STATUS: BLOCKED`；验收项没全达成 = `BLOCKED`，没有「一半 DONE」。

- `BLOCKED` 写三段：缺什么、卡在哪、部分证据已落哪。
- 状态**同时**落最终答复和看板行：下一个会话看不到你的答复。
- 判据全文见 [`protocol/01-status.md`](01-status.md)；首行是索引不是结论——之后仍要核 `DONE WHEN` 和盘上产物。

## 6. 父代只读

| 操作 | 谁做 |
|---|---|
| 读文件、搜、`git status` / `log` | 父代可以 |
| 改项目里任何被跟踪的文件 | **派工人** |
| `git commit` / `push` / 建分支 | **派工人**，父代不碰 |
| 把实现再派给第二个工人 | **不许**（工人只派一层） |

## 7. 多路：切 scope，只派前沿

- 先切**互不重叠**的写路径再派；切不出来 = 这活该串行。
- 一个 scope 一个工人；撞路径由开卡拒，不靠自觉。
- 只派**前沿**：阻塞清、未被占、没人在做。收一个 close 一个，再取下一个。
- 并发不设人为上限；真正的风险是没写报告落点、没逐个核回执。
- 一波收工三件：板对账、抽验复跑、一页复盘（[`library/recovery/retro.md`](../library/recovery/retro.md)）。

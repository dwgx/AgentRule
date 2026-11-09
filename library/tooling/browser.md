<!-- source: AgentRule/浏览器.md @ 49a892ac -->
# 浏览器
> EN: Browser rules: drive the agent Chrome on port 9333 yourself, one page per task, and close the pages you opened.
<!-- summary: 用 agent 浏览器干活：自己开页面、一任务一页、用完关掉自己开的页。 -->

想用就用。9333 上的 agent Chrome 是你的手：打开页面、点击、填写、等待、截图，都用 chrome-devtools 自己做，不用先问。你点名「开浏览器」就必须用。

| 要做 | 怎么做 |
|---|---|
| 任意页面 / 本地页 / 描绘台 | chrome-devtools：自己 `new_page`，再用 `pageId` + 快照去点、填、等 |

只挂 **9333** agent Chrome。日常 Chrome / 9222 只在必须碰你正在用的浏览器时。
新标签 `background: true`。不要 `bringToFront`。不要杀 chrome。

启动脚本：`~\.local\bin\agent-chrome-mcp.cmd`（各 harness 的 MCP 已指向它）

## 用完就 `close_page`

**自己 `new_page` 开出来的页，任务做完就 `close_page` 关掉。** 这是这台机器上唯一有效的省内存手段，不是讲究。

2026-10-01 实测（一次性 profile + 独立端口，12 个 tab 跑 12 个不同 origin）：

```
开 12 个 tab  →  500 MB 私有内存, 10 renderer
关掉全部 12  →  287 MB 私有内存,  4 renderer
```

回收率 **103%**——renderer 内存完全跟着 tab 走，关掉就彻底还回来。
失控的样子见过：20 个 renderer，其中一个冻结的进程占 **803 MB**、CPU 已经零增长，页面早停了进程还钉在那儿。

三条实测结论，别再走老路：

1. **`--renderer-process-limit=8` 是无效开关**。带着它 12 个 tab 出 11 个 renderer，删掉它还是 11 个。Chrome 按 site instance 分进程，忽略这个上限。
2. **没有可靠的"这个 tab 有人用吗"信号**。`Target.setAutoAttach` 上报的是**全部** target（不是已连接的）；后台 tab 的 freeze 事件**从不触发**。所以**不要**写自动回收脚本——这台机器上有 10 个 MCP server 共用 9333，猜错就是在关别人正在跑的活。
3. **所以只能靠规矩**：开的时候记下自己的 `pageId`，收工逐个 `close_page`。收工前 `list_pages` 对一遍，别留。

关**自己**开的页不用报备；**批量关**（单轮 ≥3 个，尤其可能碰到别人开的）仍然先报备——报备带前检（`list_pages` 现状 + 要关哪些 + 为什么），关完再 `list_pages` 对账。

## 上限与地盘

- 同一时刻的重活 **≤2**（重活 = 会新起进程 / 渲染的动作）；批量动作（关标签、改名、建删项目）**先报备**。被 429 / 限流：退避，不补发，先报数。
- 一标签一写手，别把 Owner 的工作区当自家地盘。

## 多人同开

先 `list_pages` → 自己 `new_page` → 只动自己的 `pageId`。**关：关自己的，别人的不关。** 收工把自己开的那批 `close_page` 掉。

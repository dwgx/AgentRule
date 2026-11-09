<!-- source: AgentRule/specialist/README.md @ 9f10dfc5 -->
# specialist（扩展线）索引
> EN: Index for the specialist lane: the reverse-engineering station and how the lane is wired.
<!-- summary: 逆向线入口：谁能读、和通用库怎么分工、开工先读哪页。 -->

> **谁能读本页**：身份文件里声明为 specialist 的 harness——当前 **omp / codex**。
> **官方 Claude Code 不读本页**（它的身份文件写着 CORE 档）。
> 通用页仍在 `library/README.md`（CORE 索引）；开工前先读 `library/floor/incidents.md`（CORE）照旧。

| 要干什么 | 打开 | 核对命令（无则 —） |
|---|---|---|
| 反编译 / 解包 / IDA / Ghidra / x64dbg / JADX / Il2Cpp / Frida | `library/specialist/reverse-station.md`（必须）+ skill `debugger-workstation` | — |
| 站线活收尾（双轴 review / 沉淀） | skill `debugger-review` | — |

## specialist 接线

- skills：omp / codex 的 skill 目录接到站的 `debugger-workstation` / `debugger-review`；官方 Claude Code 已摘除。
- MCP：到站才挂 `debugger-router`，不并进用户全局（细则 `library/specialist/reverse-station.md`）。
- 硬地板的军火库例外（<program-a> + debugger 站）仍写在 CORE 的 `library/floor/hard-floor.md`——对 specialist 线照旧生效。

删条: 分层取消（官方 Claude 与 specialist 并回一份索引）→ 删本文件、行并回 `library/README.md`。

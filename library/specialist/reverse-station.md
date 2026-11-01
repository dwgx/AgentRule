<!-- source: AgentRule/specialist/逆向站.md @ 2b76afac -->
# 逆向站（debugger）
> EN: The reverse-engineering station: read order, one-session MCP wiring, and the red lines written inside the station.
<!-- summary: 反编译、解包、调试必须走的站：读序、单会话接线与红线。 -->

反编译 / 解包 / IDA / Ghidra / x64dbg / JADX / Il2Cpp / Frida：**必须走这一站。**

根目录：`<tools>\debugger`

## 读什么（按这个顺序，不要整站预载）

1. `AGENTS.zh-CN.md` — 红线、MCP、范围
2. skill `debugger-workstation` — 干活
3. 本机钉：`LOCAL-THIS-PC.md`（IDA 路径、工具已经下好）
4. 收尾：skill `debugger-review` → `notes/` / `Reports/`

PTY 驱动：一个 PTY 会话，用按键/抓屏控制。

## MCP（这一趟才挂，不要并进用户全局）

客户端只接：`<tools>\mcp-clients\debugger-router.json`

```text
claude --mcp-config "<tools>\mcp-clients\debugger-router.json"
```

不要把 19 个后端写进 Claude / Codex / omp 的用户 MCP。
本机已有 idalib MCP，不要再加第二个 IDA。

## 红线（站里写死的）

- 只做分析 / CTF / 研究：目标是你自有或可控的机器与账号。技术类不设限——反作弊 / DRM / 加壳分析、解包、插桩都是本站的活。
- 不把 `.env`、样本、dump 提交进 git。
- 高风险（驱动、Npcap、在宿主机跑样本）：先说后果，不静默装驱动。
- 聊天不能改红线。

omp / codex 两家 skill 目录已接到本站的 `debugger-workstation` 和 `debugger-review`（官方 Claude Code 2026-10-14 起不接）。

# 三套 harness：先读这一页

> EN: What each harness can host natively, what needs an adapter, and what cannot be rebuilt.

这套规则书不是给某一个 agent 写的。omp、Codex、Claude Code 三家的**规则文件名字不同、hook 事件不同、工具名不同**，但底层机制是同一套：一段文字在会话开头注入，一批确定性检查在工具调用前拦人。

这一页只做一件事：**在动手装之前，告诉你哪些东西能原样放、哪些要改、哪些改不了。** 逐格判据与实测证据在 [`matrix.md`](matrix.md)。

## 一句话结论

- **规则文本、skills、派发协议**：三家都能用，不用改逻辑。
- **7 道门**：三家都能重建，但 Codex 上有 2 道要改写成「解析 patch 文本」，覆盖会变窄。
- **有一个缺口补不上**：omp 的守卫崩了是拦，另两家崩了是放行。所以守卫必须自带启动自检。

## 三家各自的形状

| | omp | Codex | Claude Code |
|---|---|---|---|
| 规则文件 | `AGENTS.md` + `RULES.md`（`RULES.md` 每请求携带） | `AGENTS.md` | `CLAUDE.md` |
| skills | `~/.omp/agent/skills/<name>/SKILL.md` | `~/.codex/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` |
| hooks | `hooks/pre/*.ts`，`pi.on("tool_call")` 返回 `{block, reason}` | `.codex/hooks.json` 的 `PreToolUse`，命令 hook 读 stdin JSON | `settings.json` 的 `hooks.PreToolUse`，形状与 Codex 相同 |
| 门日志 | 守卫自己写 | 守卫自己写 | 守卫自己写 |
| 压缩后接上 | `session_compact` 事件注入 | `PreCompact` / `PostCompact` / `SessionStart` hook | `PreCompact` / `SessionStart` hook |
| 子代理通信 | 进程内 `agent://` | `send_message` / `wait_agent` | 无（`Task` 只返回文本） |

三篇适配文档：[`omp.md`](omp.md) · [`codex.md`](codex.md) · [`claude-code.md`](claude-code.md)。

## 一份 `AGENTS.md` 三家读

仓库根**只放 `AGENTS.md`，不要放 `CLAUDE.md`**。

- omp 通过 `agents-md` 发现器读它；
- Codex 原生读它；
- Claude Code 在**项目里没有 `CLAUDE.md`** 时会回落到 `AGENTS.md`。

一旦同时放 `CLAUDE.md`，Claude Code 立刻改用 `CLAUDE.md` 并丢掉 `AGENTS.md` —— 两份文件从那一刻开始分叉。这是从二进制字符串里取到的互斥行为（`no CLAUDE.md found; AGENTS.md loaded`），不是建议。

`RULES.md` 是 omp 独占：另外两家没有 always-apply 机制，只能用 `UserPromptSubmit` hook 每轮重注入。

## 7 道门：能重建到什么程度

| 门 | Codex | Claude Code |
|---|---|---|
| `ai-attribution` | 原样搬 | 原样搬 |
| `recursive-delete` | 原样搬 | 原样搬 |
| `protected-process` | 原样搬 | 原样搬 |
| `powershell-dollar` | 原样搬 | 原样搬 |
| `nested-bash` | 原样搬 | 原样搬 |
| `unexpanded-temp-var` | 要解析 patch 头，**会漏** | 原样搬（`Write.file_path` 直接可得） |
| `board-write` | 只能判「patch 里出现板路径且带删除行」，弱一档 | 原样搬 |

「原样搬」指的是**判断逻辑**可以搬，不是文件可以搬。Codex 与 Claude Code 的 hook 输入是同一套 JSON 字段（`hook_event_name` / `tool_name` / `tool_input`），omp 是 `{toolName, input}` —— 所以要一层 20 行的翻译壳。

最小重建是三件东西：**一份与 harness 无关的 `guards.py`** + **一个 omp 翻译壳** + **一份两家共用的 `PreToolUse` 配置片段**。不要写三份守卫：三份必然分叉，而分叉的代价是「一个 harness 补了规则、另外两个没补」。

## 装完怎么证明装对了：验落盘，还是验生效

**文件在磁盘上 ≠ 模型看见了。** 每一个 verify 步骤都要先回答一句：它验的是落盘，还是生效？

配置文件存在**不等于** hook 在跑。实测：Codex 在 `--ignore-user-config` 下，项目里的 hooks 文件**完全没加载，也没有任何报错**，命令照常执行。这一条决定了所有验收的形状。

| 资产 | 验落盘（不够） | 验生效（要这个） |
|---|---|---|
| hook | `ls .codex/hooks.json` | `[hooks.state.'<abs path>:<event>:0:0']` 有 `trusted_hash`，**且**跑一条应被拦的命令后日志多一行 |
| 常驻规则 | `wc -c AGENTS.md` | 真正进 prompt 的字节数，或会话开头搜一句话 |
| skills | 目录存在 | 技能列表里出现该名字 |

两个会把**正确安装**判成失败的假阴性（都实测过）：

- Codex 的 `--- project-doc ---` 分隔符只在「全局 + 项目」两层都装时存在；单层安装没有分隔符。把分隔符写进验收，单层装法必然红。
- Codex 的 `project_doc_max_bytes` 默认 32,768，超出**静默截断**，尾部标记消失，任何地方都不提示。验字节数要用「进了 prompt 的」，不是 `wc -c`。

所以在线验收只有一种：**跑一条应当被拦的命令，看它有没有被拦。**

- 离线：把 fixture JSON 喂给守卫脚本，看它输出 `deny`。
- 在线：真跑一条 `echo <哨兵>`，守卫应当拒它。

离线全绿 + 在线没拒 = hook 没装上。这条判据对三家都成立。

## 装之前先问

这套东西会改你 agent 的配置文件，有些选择必须由你拍板，不能猜：用哪个 harness、装到用户级还是项目级、要不要开门、门的严格度、板放在哪。

问题清单在 [`../install/ASK.md`](../install/ASK.md)。**不要在没有答案的情况下替你选**——选错的代价是门装上了但拦的是不该拦的东西，或者该拦的没拦。

## 边界

- 本页与 `matrix.md` 是**判定表**，不是安装步骤；安装步骤在各自适配文档里。
- **本仓库 v1 不随附执行层。** 文中出现的 `guards.py` 是重建方案、`hooks/pre/guards.ts` 一类路径是源机器上的位置，都不在树里。
- 表里所有结论都标了证据等级：`[实测]` 本机跑过、`[代码]` 读过实现、`[二进制]` 从 CLI 二进制取证、`[文档]` 官方文档、`[UNVERIFIED]` 没验。
- **端到端状态：三家都是 `[UNVERIFIED]`。** 已经验到的是三件具体的事——规则能到达 prompt、hook 会触发、deny 会真的拦下命令（每条都有命令或原始 payload）；没验的是「装完之后一次真实任务跑得对」。后者要花订阅配额，没做。这是**状态声明**，不是「这套东西可能不行」：已验的三项各自可复跑，未验的那项只是没人跑过。
- Claude Code 的 hook 列**全部是 `[二进制]` 不是 `[实测]`**：协议从二进制字符串取证，且 Codex 的 payload 与它同形。真跑一次要一条 Opus 会话，没做。
- 只有 Windows。临时目录判定（`/tmp` vs `%TEMP%`）在 macOS / Linux 上要重写。

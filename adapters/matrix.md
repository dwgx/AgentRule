# 三套 harness 对照表（逐格判据）

> EN: The per-cell evidence behind the adapter decision page: 12 asset classes, 3 harnesses, 36 verdicts.

本页是 [`README.md`](README.md) 的证据层。每个格子都带证据等级；每个判定都对应一个能在本机重跑的动作。

## 1. 判据口径

### 1.1 三档定义（逐词标可判性）

| 词 | 可判？ | 判据（判定动作） |
|---|---|---|
| 原生支持 | 可判 | harness 自带该资产的发现路径**且**有执行语义；用户只放文件、不写胶水。动作：放一份最小样例，看它是否被加载或执行。 |
| 需改造 | 可判 | harness 有等价机制，但文件格式 / 字段名 / 触发点 / 工具名不同，必须写一层适配。动作：指出「改哪一行」，给出改造前后两个名字。 |
| 不支持 | 可判 | 既无发现路径也无执行点，只能降级成提示词。动作：二进制与配置 schema 里都搜不到该事件或目录，且文档无等价物。 |
| 为什么 | 可判 | 必须落到机制差异（文件名 / 事件名 / 字段名 / 信任模型），不能写「设计不同」。 |

### 1.2 证据等级

`[实测]` 本机跑过，附命令或原始 payload · `[代码]` 读过实现 · `[二进制]` 从 CLI 二进制字符串取证 · `[文档]` 官方文档 · `[INFERENCE]` 推断 · `[UNVERIFIED]` 没验

### 1.3 本机基线（2026-11-02）

| 项 | omp | Codex | Claude Code |
|---|---|---|---|
| 版本 | 本机 agent 目录 `~/.omp/agent` | codex-cli 0.165.0 | 2.1.306 |
| 规则文件 | `AGENTS.md` + `RULES.md` | `AGENTS.md` | `CLAUDE.md`（**本机不存在**） |
| skills 数量 | 17 | 7 | 2 |
| hooks 是否在用 | 是（`pre/guards.ts` + `post/` 4 个） | 是（`features.hooks = true`） | **否**（`settings.json` 里没有 `hooks` 键） |
| 审批模式 | `tools.approvalMode: yolo` | `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` | `permissions.defaultMode: "bypassPermissions"` |

> **本节与后文出现的路径都是源机器上的位置，不是本仓库的文件。** `~/.omp/agent/hooks/pre/guards.ts`、`hooks/post/*.ts`、`run_all_gates.py`、`hook_probe.py` 一个都不随仓库发货；`guards.py` 是 §3.1 的重建方案，同样不在树里。本仓库 v1 不随附执行层——这条适用于全文。

## 2. 12 类资产 × 3 harness

判定后括号里是证据等级；`判据` 列是**同一个动作在三个 harness 上各跑一次**；`验落盘/验生效` 列见 §5。

**每一格 = 该行的判据动作在对应 harness 上跑一次的结果**；格内括号里的证据等级指向 §4 的实测 payload 或 §8 的口径说明。

| # | 资产 | omp | Codex | Claude Code | 判据（怎么验） | 验落盘/验生效 | 差异原因 |
|---|---|---|---|---|---|---|---|
| A1 | 规则文本（常驻规则页） | 原生支持 `[文档]` | 原生支持 `[代码]` | 需改造：改名为 `CLAUDE.md`，或保证仓里没有 `CLAUDE.md` `[二进制]` | 放一份最小 `AGENTS.md`，看会话开头有没有出现它的内容 | 验生效 | 记忆文件名不同；Claude Code 有互斥回落 |
| A2 | 硬地板（44 条禁令） | 原生支持 `[实测]` | 需改造：5 条搬、2 条改 `[实测]` | 需改造：5 条搬、2 条改 `[二进制]` | 跑 [`hard-floor.md`](../library/floor/hard-floor.md) 头部那段自查命令；原稿实测输出 `门=9 停=11 提示=24 无标记=0 共=44`。**门数 9 是原机器的历史事实，副本不改数**；要查的是「伴生工具清单有没有声明这些工具不随仓库发货」 | 验生效 | 执行层是 hook，hook 输入形状不同 |
| A3 | 卡（W 档十张执行卡） | 原生支持：`hooks/post/tier-card.ts` 在 `context` 事件按模型档位追加到消息尾部 `[代码]` | 需改造：`UserPromptSubmit` + `additionalContext` `[二进制]` | 需改造：同上 `[二进制]` | 弱档模型跑一轮，看尾部有没有卡文本；强档跑一轮，应无 | 验生效 | 注入点不同；另两家没有「模型档位」概念，只能按 `model` 字段自己判 |
| A4 | skills | 原生支持：`~/.omp/agent/skills/*/SKILL.md`（17 个）`[代码]` | 原生支持：`~/.codex/skills/*/SKILL.md`（7 个）`[代码]` | 原生支持：`~/.claude/skills/*/SKILL.md`（2 个）`[代码]` | 放一个 `SKILL.md`，看它是否出现在可用技能列表里 | 验生效 | 目录不同，frontmatter 格式相同 |
| A5 | hooks / 门 | 原生支持：`hooks/pre/*.ts` + `pi.on("tool_call")` → `{block, reason}` `[代码]` | 需改造：`.codex/hooks.json` 的 `PreToolUse`，要过 trust `[实测]` | 需改造：`settings.json` 的 `hooks.PreToolUse` `[二进制]` | 放一个只会 deny 的 hook，跑一条命令，看它是否被拦（§4.1 第 3 次） | 验生效（`[hooks.state]` 有 hash **且**日志多一行） | 见 §3 |
| A6 | 派发协议（板 + brief 检查 + STATUS） | 原生支持：`task` 工具 + `agent://` + `maxRecursionDepth: 2` `[代码]` | 需改造：`spawn_agent` / `send_message` / `wait_agent`，`max_depth = 2` `[代码]` | **不支持**子代理互发消息：`Task` 只返回文本 `[二进制]` | 派两个子代理，让 B 给 A 发一条消息，看 A 是否收到 | 验生效 | 通信拓扑不同：omp 进程内、Codex 有显式投递、Claude Code 无 |
| A7 | 恢复协议（压缩/重启接上） | 原生支持：`session_compact` + `hooks/post/recover-pointer.ts` 注入 followUp；4 种压缩法 `[代码]` | 需改造：`PreCompact` / `PostCompact` / `SessionStart` hook `[实测]` | 需改造：`PreCompact` / `SessionStart` hook `[二进制]` | 触发一次压缩，看压缩后第一条消息里有没有指针 | 验生效 | omp 有 `session_before_compact` 可改压缩结果；另两家只能事后注入 |
| A8 | 常驻注入通道（always-apply） | 原生支持：`RULES.md` 每请求携带 `[文档]` | 需改造：`UserPromptSubmit` 每轮重注入 `[二进制]` | 需改造：同上 `[二进制]` | 长会话跑到上下文过半，看规则文本是否还在 | 验生效 | 引擎级 vs hook 级；后者破坏 prompt cache 前缀 |
| A9 | 审批与沙箱 | 原生支持：`tools.approvalMode: yolo` `[代码]` | 原生支持：`approval_policy` + `sandbox_mode` `[代码]` | 原生支持：`permissions.defaultMode` `[代码]` | 读配置键 | 验落盘（配置键即生效值，`--strict-config` 兜底） | 语义分层不同：Codex 的 sandbox 在 hook 之外还有一层 |
| A10 | 子代理与并行 | 原生支持 `[代码]` | 原生支持 `[代码]` | 原生支持 `[二进制]` | 一次起 2 个并行子任务 | 验生效 | 并发上限与深度上限不同（omp 2 层、Codex 4 线程 / 2 层） |
| A11 | 审计日志 | 需改造：`hooks/log/bash.<hour>.log` 由守卫自己写 `[代码]` | 需改造：hook 自己写；payload 带 `transcript_path` `[实测]` | 需改造：同 Codex `[二进制]` | 触发一次 block，看日志里有没有 `rule` + `hit` | 验生效 | 三家都没有内建的门审计，必须守卫自写 |
| A12 | 验收（证明装对了） | 原生支持：`run_all_gates.py`（离线 fixture + 负控）+ `hook_probe.py` `[实测]` | 需改造：离线 fixture 喂 stdin + 一条真调用 `[实测]` | 需改造：同 Codex `[二进制]` | 先离线喂 fixture，再真跑一条应当被拦的命令 | 验生效 | Codex/Claude Code 缺「hook 真的被加载」的静态证明；没加载时不报错 |

**格数**：12 类 × 3 = 36 格 —— 原生支持 18、需改造 17、不支持 1（脚本从本表数出）。

## 3. 7 道门逐门对照

omp 的 7 道门在 `hooks/pre/guards.ts` 的 `GUARDS` 数组里，`[代码]` 实测 7 条 id 与 [`hard-floor.md`](../library/floor/hard-floor.md) 的 `【门:guards.ts X】` 一一对应（7/7，零差集）。

| 门 | omp 输入 `[代码]` | Codex 输入 `[实测]` | Claude Code 输入 `[二进制]` | 重建 |
|---|---|---|---|---|
| `ai-attribution` | `bash.input.command` | `Bash.tool_input.command` | `Bash.tool_input.command` | 三家都能，正则原样搬 |
| `recursive-delete` | `bash.input.command` | `Bash.tool_input.command` | `Bash.tool_input.command` | 三家都能 |
| `protected-process` | `bash.input.command` | `Bash.tool_input.command` | `Bash.tool_input.command` | 三家都能 |
| `powershell-dollar` | `bash.input.command` | `Bash.tool_input.command` | `Bash.tool_input.command` | 三家都能 |
| `nested-bash` | `bash.input.command` | `Bash.tool_input.command` | `Bash.tool_input.command` | 三家都能 |
| `unexpanded-temp-var` | `write.path` / `edit.path` | `apply_patch.tool_input.command`（**patch 全文**） | `Write.file_path` / `Edit.file_path` | Codex 要解析 `*** Add File:` / `*** Update File:` 头，**会漏**：模型可以在 patch 正文里写一个不带头的路径 |
| `board-write` | `bash.command` + `write/edit` 的 path+content | patch 全文；「截断」要看 `-` 行 | `Bash` + `Write`/`Edit` | Codex 只能判「patch 里出现板路径且带删除行」，比 omp 弱一档 |

### 3.1 最小重建：三件东西

1. **`guards.py`（一份，与 harness 无关）**
   从 stdin 读 `{harness, tool_name, tool_input, cwd}`，往 stdout 写 `{"decision": "deny"|"allow", "rule": "...", "reason": "..."}`。7 条规则、临时目录边界、限时放行全在这里。
2. **omp 翻译壳 `hooks/pre/guards.ts`（约 20 行）**
   `pi.on("tool_call")` 拿 `{toolName, input}` → 起子进程喂 `guards.py --harness omp` → 把 `deny` 翻成 `{block: true, reason}`。
3. **一份 `PreToolUse` 配置片段，Codex 与 Claude Code 共用**
   `matcher` + `type: "command"` + `command: python .../guards.py`。

不要写三份守卫：三份必然分叉，而分叉的代价是「一个 harness 补了规则、另外两个没补」——这套规则书的历史里，同一个错犯第二遍才够格改规则书（见 [`incidents.md`](../library/floor/incidents.md)）。

### 3.2 补不上的部分

| 缺口 | 具体是什么 | 后果 |
|---|---|---|
| **fail-closed 语义** | omp：守卫抛异常 → 拦。Codex / Claude Code：exit 2 才拦，其它非零是「非阻塞错误」，没有 stdout 决策就是放行 | 守卫自己崩了，omp 停、另两家继续跑。重建后必须加自检：启动时先跑内置 fixture，失败就 exit 2 |
| **`task` / `browser` 工具级拦截** | omp 的 `EFFECTFUL_TOOLS` 含 `task`、`browser`；Codex 对应 `spawn_agent`，Claude Code 对应 `Task` | 这两者会不会触发 `PreToolUse`，**没测** `[UNVERIFIED]`。没测就不能假设有覆盖 |
| **主动调用型的两道门** | 板占坑 + brief 检查、收工 `--verify` 不是 hook，是「agent 主动跑才生效」 | 三家完全一样：都不跑就没有。这不是 harness 差异，是协议差异 |
| **trust 门** | Codex 的 hooks 文件要过 trust（`[hooks.state]` 记 `trusted_hash`），改一个字节 hash 就变 | 部署时多一步人工确认；旁路开关是「本次调用」级别，不是配置级 |

## 4. 实测记录：Codex 的 hook 到底长什么样

2026-11-02 在临时工程里放 `.codex/hooks.json`（`PreToolUse` + `PostToolUse` + `SessionStart`，matcher `.*`），hook 脚本把 stdin 原样追加到日志，跑三次 `codex exec`。

### 4.1 三次实验的差别

| 次 | 参数 | 结果 |
|---|---|---|
| 1 | `--ignore-user-config --enable hooks --dangerously-bypass-hook-trust` | **hook 一次没触发**（日志文件根本没生成），命令照常执行，**没有任何报错** |
| 2 | 同上，去掉 `--ignore-user-config` | hook 触发，日志生成 |
| 3 | 同 2，prompt 要求跑 `echo DENYME`，hook 返回 deny | 命令被拦：`Command blocked by PreToolUse hook: probe: DENYME blocked by PreToolUse hook. Command: echo DENYME` |

**第 1 次是最值钱的一条**：hook 没加载时 Codex 不报错。所以「装好了」不能靠配置文件存在来证明，只能靠真跑一次。

### 4.2 原始 payload（路径已替换成 `~`）

`SessionStart`：

```json
{"session_id":"<uuid>","transcript_path":"~\\.codex\\sessions\\<date>\\rollout-<ts>-<uuid>.jsonl","cwd":"<probe-dir>","hook_event_name":"SessionStart","model":"gpt-6-sol","permission_mode":"bypassPermissions","source":"startup"}
```

`PreToolUse`（模型跑了 `echo hookprobe`）：

```json
{"session_id":"<uuid>","turn_id":"<uuid>","transcript_path":"~\\...jsonl","cwd":"<probe-dir>","hook_event_name":"PreToolUse","model":"gpt-6-sol","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"echo hookprobe"},"tool_use_id":"exec-<id>"}
```

`PreToolUse`（模型写文件）：

```json
{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: probe-target.txt\n+hi\n*** End Patch"}}
```

### 4.3 从这三条 payload 读出来的四件事

1. **Codex 的 hook payload 是 Claude Code 的形状**：`hook_event_name` / `tool_name` / `tool_input` / `permission_mode` / `transcript_path` 全同名。⇒ 同一份守卫脚本，两家可以共用。
2. **工具名是 Claude 名，不是 Codex 内部名**：shell 命令归一成 `tool_name: "Bash"`；文件编辑是 `apply_patch`，`tool_input.command` 是**整段 patch 文本**。这是 §3 里那两道门要改造的唯一原因。
3. **pre 事件按嵌套工具调用逐次触发**：模型表面只调了一个 `exec`（V8 跑 JS），hook 收到的是 JS 里那次 `tools.exec_command` 的**命令字符串**。⇒ 不需要扫 JS 源码。
4. **deny 用 Claude 的 `hookSpecificOutput.permissionDecision` 生效**，不是 exit code。

## 5. 验收：文件存在 ≠ 模型看到了

这一节是给所有适配文档的验收步骤定的规矩。**每一个 verify 都必须回答：它验的是落盘，还是生效？**

### 5.1 两个已实测的假阴性

这两条由 Codex 适配线实测，本表复述结论。

**（1）Codex 的 `--- project-doc ---` 分隔符是有条件的。** 三种装法三种形状：

| 装法 | 头部 | 分隔符 |
|---|---|---|
| 全局 + 项目 | `# AGENTS.md instructions for <cwd>` | 有 |
| 只有全局 | 头部**没有** `for` | **没有** |
| 只有项目 | 头部**有** `for` | **没有** |

把「分隔符必须存在」写进验收，会把一次**正确**的单层安装判成失败。`[实测]`

**（2）`project_doc_max_bytes` 截断是静默的。** 本机默认 32,768 字节：一份 40,000 字节的 `AGENTS.md` 进去只剩 32,768，尾部标记消失，**任何地方都不提示**。抬到 65,536 后 40,000 全进。`[实测]`

### 5.2 每一类该验什么

| 资产 | 验落盘（不够） | 验生效（要这个） |
|---|---|---|
| hook | `ls .codex/hooks.json` | `[hooks.state.'<abs path>:<event>:0:0']` 有 `trusted_hash`，**且**跑一条应被拦的命令后日志多一行 |
| 常驻规则 | `wc -c AGENTS.md` | 真正进 prompt 的字节数（见 5.1 第 2 条），或会话开头搜一句话 |
| skills | 目录存在 | 技能列表里出现该名字 |
| 卡 / 常驻注入 | 文件在 | 弱档模型跑一轮后，消息尾部有卡文本 |
| 恢复指针 | hook 文件在 | 压缩后第一条消息里有指针 |

**通用判据**：凡是「配置里写了」的，都不算证明；凡是「跑一次之后能看到痕迹」的，才算。

### 5.3 探针的设计约束（给写 probe 脚本的人）

1. **探针必须「守卫不在时也无害」。** 不能拿 `rm -rf` 当探针：守卫没装就真删了——**一个会误伤的探针比没有探针更危险**。正确形态是**哨兵规则 + 无害副作用**：守卫里加一条只匹配 `agentrule-probe` 的规则，探针命令是 `printf probe > "$PROBE_DIR/agentrule-probe.flag"`；判绿条件是**这个文件没生成**。
2. **不要靠「输出里有没有哨兵字符串」判。** 提示词里带着同一个字面量，harness 回显提示词就会假红。用文件副作用判，不受回显影响。
3. **Codex 侧不要加 `--ignore-user-config`**：实测它连带让 hook 不加载且不报错，那正是假绿的来源。
4. **退出码用 2 不用 1**：Claude Code 把非 2 的非零退出当「非阻塞错误」，等于放行。
5. **没有守卫时探针应当 SKIP 而不是 FAIL。** 本仓库 v1 不发执行层，所以默认状态下没有东西可验——那是「没装」，不是「装坏了」。生效探针要 `--live` 显式开：它要起进程、要联网、要烧配额，不该混进「装完 3 秒给结论」的健康检查里。

## 6. 一份文件三家读

这条决定仓库里到底该放哪些文件。`[二进制]` 证据在括号里。

| 文件 | omp | Codex | Claude Code |
|---|---|---|---|
| `AGENTS.md`（仓库根） | 读（`agents-md` 发现器） | 读（原生，`project_doc_max_bytes` 默认 32768） | **只在没有 `CLAUDE.md` 时**读（二进制串：`no CLAUDE.md found; AGENTS.md loaded`） |
| `CLAUDE.md` | 读（`claude` 发现器，需 `enabledProviders`） | 不读 | 读 |
| `RULES.md` | **读，且是 sticky**（每请求携带） | 不读 | 不读 |
| `~/.codex/AGENTS.md` | 读（需 opt-in） | 读 | 不读 |
| `SKILL.md` | 读（`~/.omp/agent/skills/*`） | 读（`~/.codex/skills/*`） | 读（`~/.claude/skills/*`） |
| `.codex/hooks.json` | 不读 | 读 | 不读 |
| `settings.json` 的 `hooks` | 不读 | 不读 | 读 |

**结论**：仓库根**只放 `AGENTS.md`，不放 `CLAUDE.md`**。这样 omp 读、Codex 读、Claude Code 因为没有 `CLAUDE.md` 而回落 —— 一份文件三家生效。一旦同时放 `CLAUDE.md`，Claude Code 立刻改用 `CLAUDE.md` 并丢掉 `AGENTS.md`，两份文件开始分叉。

## 7. 边界行

按另一种读法会**改判**的行，逐行列出：

| 行 | 现在判 | 另一种读法 | 为什么我这样判 |
|---|---|---|---|
| A1 · Claude Code | 需改造 | 原生支持（它确实会读 `AGENTS.md`） | 那是**互斥回落**不是支持：仓里一旦出现 `CLAUDE.md`，`AGENTS.md` 立即失效。判据是「放文件就生效」，不是「某种条件下会读」。 |
| A8 · Codex | 需改造 | 原生支持（`UserPromptSubmit` 每轮注入） | 不是引擎级 always-apply：它破坏 prompt cache 前缀，且模型可无视。omp 的 `RULES.md` 是随请求携带的规则对象，语义不同。 |
| A5 · Codex | 需改造 | 原生支持（事件、决策协议、matcher 全都有） | 默认路径要过 trust，且**没加载时不报错**（§4.1 第 1 次）。「要人工确认 + 失败静默」不是原生支持的定义。 |
| A6 · Claude Code | 不支持 | 原生支持（`Task` 能派活） | 只看「能派活」是原生支持；但协议里还有「子代理互相核对」。Claude Code 没有 agent 间投递通道，那一半只能退化成写盘。按**整类**判，判不支持。 |
| A11 · 三家 | 需改造 | 原生支持（每家都有 transcript / rollout 记录） | transcript 不是门日志：它不记录「哪条规则拒了哪次调用」。门日志只能由守卫脚本自己写。 |
| A12 · Codex/Claude Code | 需改造 | 原生支持（有 `codex exec` / `claude -p` 可跑） | 能跑 ≠ 有验收：两家都没有「门是否加载」的自证；omp 的 `hook_probe.py` 会比对日志字节增量。缺的是**判据**，不是命令。 |

## 8. 本表不证明什么

- **没在 Claude Code 上真跑 hook。** 它的 hook 协议是从二进制字符串取证的（`PreToolUse` / `PostToolUse` / `permissionDecision` / `hookSpecificOutput` / `exit code 2` / `non-blocking status code`），加上 Codex 的 payload 与它同形。真跑一次要一条 Opus 会话，成本与收益不划算 ⇒ Claude Code 列全部标 `[二进制]`。
- **端到端状态：三家都是 `[UNVERIFIED]`。** 已经验到的是三件具体的事——规则能到达 prompt、hook 会触发、deny 会真的拦下命令（§4 有原始 payload）；没验的是「装完之后一次真实任务跑得对」。后者要花订阅配额，没做。这是状态声明，不是「这套东西可能不行」。
- **没测 `spawn_agent` / `Task` 是否触发 `PreToolUse`。** 子代理工具调用是否过门，未知 `[UNVERIFIED]`。
- **没测 Codex 的 plugin 提供的 hook**（二进制里有 `plugin.json#hooks`），只测了项目级 `.codex/hooks.json`。
- **没测 trust 的交互流程**（TUI 里怎么弹、`trusted_hash` 什么时候重算），只测了旁路开关。
- **只有 Windows。** 临时目录判定（`/tmp` vs `%TEMP%`）在 macOS / Linux 上要重写。
- **本页不是安装文档。** 具体路径、命令、回滚在 [`omp.md`](omp.md)、[`codex.md`](codex.md)、[`claude-code.md`](claude-code.md)。

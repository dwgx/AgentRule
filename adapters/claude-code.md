<!-- measured on @anthropic-ai/claude-code 2.1.306, Windows, 2026-11-02 -->
# Claude Code 适配
> EN: Where Claude Code's resident file, hooks and skills live, and how to prove they loaded.

本文是 `adapters/` 的一篇，写给**别人的 agent**读：你拿到这个仓库，要用它把这台机器上的 Claude Code 配好。读完你应当能直接执行，不用回头问人；唯一该问人的地方在第 2 节，**那 5 个问题不许猜**。

规则的正文不在本文——本文只讲「怎么装进去」。规则本体在 `library/`，协议在 `protocol/`。

---

## 0. 一句话结论

Claude Code 的规则入口是 **`~/.claude/CLAUDE.md`**（用户级）+ **`./CLAUDE.md`**（项目级）+ **`.claude/rules/`**（分文件）；它的门是 **`settings.json` 里的 `hooks` 段，值是 shell 命令**，跟 omp 的 TypeScript 门**是两套东西，不能复制**。7 道门里只有 **3 道值得翻**，另 3 道是本机 Windows 怪癖，1 道依赖本机看板脚本。

**动任何文件之前，先做第 2 节那 5 个问题。** 猜错作用域 = 覆盖用户已有配置。

---

## 1. 实测基线：这台机器上的 `~/.claude/`

以下不是文档抄的，是 2026-11-02 在 Windows 上实跑出来的。复现命令与输出原文见 1.3。

### 1.1 顶层

| 路径 | 类型 | 大小 | 文件数 | 是什么 |
|---|---|---|---|---|
| `~/.claude/settings.json` | 文件 | 945 B | 1 | **唯一的活配置**。用户级设置 |
| `~/.claude/settings.json.bak.20261021T103916` | 文件 | 728 B | 1 | 手工备份，不是 Claude Code 生成的 |
| `~/.claude/history.jsonl` | 文件 | 2,325 B | 1 | 输入历史（纯 prompt 文本 + cwd + sessionId） |
| `~/.claude/.last-cleanup` | 文件 | 24 B | 1 | 清理时间戳 `2026-11-01T22:27:27.370Z` |
| `~/.claude/skills/` | 目录 | 1.8 K | 2 | **规则入口之一**，见 1.2 |
| `~/.claude/plugins/` | 目录 | 58 M | 2,706 | 插件缓存。本机只有 `claude-hud` 一个状态栏插件 |
| `~/.claude/projects/` | 目录 | 3.5 M | 10 | 会话转录 `*.jsonl`，按项目路径分目录 |
| `~/.claude/cache/` | 目录 | 1.3 M | 4 | changelog、模型目录、已关 issue |
| `~/.claude/backups/` | 目录 | 279 K | 5 | `.claude.json` 的历史备份 |
| `~/.claude/sessions/` | 目录 | 659 B | 2 | 会话锁：`<id>.json` + `<id>.key` |
| `~/.claude/shell-snapshots/` | 目录 | 0 | 0 | 空 |
| `~/.claude/session-env/` | 目录 | 0 | 0 | 空（只有一个空目录 `755b5b77-…`） |

合计 **2,729 个文件 / 522 个目录 / 63 MB**。

**结论：63 MB 里 61 MB 是插件和会话转录，配置只有 945 B。** 装规则不需要碰那 61 MB，也不要把它复制进任何仓库。

### 1.2 两个真正的规则入口

本机 `~/.claude/skills/` 只有两个 skill，**而且两个都是「指针文件」，不是正文**：

```
~/.claude/skills/dispatch/SKILL.md      993 B
~/.claude/skills/i-have-adhd/SKILL.md   812 B
```

`dispatch/SKILL.md` 正文：

```markdown
---
name: dispatch
description: >-
  Dispatch an authorized bounded task through OMP native task or an existing native CLI, ...
---
# dispatch (pointer)

Canonical copy: `<omp 配置目录>/skills/dispatch/SKILL.md`

This directory is a pointer, not a second copy: the body lives only at the canonical path
above, and edits here are lost at the next sync.
```

⚠️ **这是本机的私有做法，开源仓库里绝对不能照抄。** 开源用户的机器上没有 `~/.omp/agent/skills/`，复制这个指针文件过去，得到的是一个指向不存在路径的 skill——`description` 会被加载、正文永远读不到。**本仓库的安装步骤一律复制正文。**

### 1.3 复现命令

```bash
cd ~ && find .claude -maxdepth 3 | sort          # 顶层结构
cd ~ && find .claude -type f | wc -l             # 2729
cd ~ && find .claude -type d | wc -l             # 522
cd ~ && du -sh .claude                           # 63M
cd ~/.claude && du -sh backups cache plugins projects sessions shell-snapshots skills session-env
cd ~/.claude && for d in *; do printf "%-18s %s\n" "$d" "$(find "$d" -type f 2>/dev/null | wc -l)"; done
```

### 1.4 一个反直觉的实测结果

**本机没有用户级 `CLAUDE.md`。**

```bash
cd ~ && for f in CLAUDE.md .claude/CLAUDE.md .claude/CLAUDE.local.md; do
  [ -f "$f" ] && echo "FOUND $f" || echo "MISSING $f"
done
# MISSING CLAUDE.md
# MISSING .claude/CLAUDE.md
# MISSING .claude/CLAUDE.local.md
```

也就是说：这台机器跑 Claude Code，**一行常驻规则都没装**，只有 2 个指针 skill 和 945 B 的 settings。别把「这台机器配好了」当成默认前提——**装之前先查**，这正是第 2 节第 1 问的由来。

---

## 2. 部署前必须问的 5 个问题

规则：**这 5 个问题没得到回答之前，不许写任何文件。** 猜错的代价是覆盖用户已有配置，或者装了一个永远不会触发的门（见 7.2）。

把下面整段原样发给用户，等他答：

```
我要往你的 Claude Code 里装 AgentRule，需要你确认 5 件事（直接答编号即可）：

1. 你现在有用户级 CLAUDE.md 吗？（路径 ~/.claude/CLAUDE.md）
   A) 没有    B) 有（有的话我要合并，不是覆盖）
2. 装在哪个作用域？
   A) 用户级（~/.claude/）：所有项目都生效
   B) 项目级（<项目>/.claude/）：只在这个项目生效，可以进 git 跟团队共享
3. 要不要装「门」（hooks）？
   门 = 在工具执行前用脚本拦下危险操作。
   A) 装：需要 Python；hook 写错会让整份 settings.json 被 Claude Code 静默忽略（见 3.5）
   B) 不装：只有规则，靠模型自觉
4. 你的 Claude Code 版本？（跑 claude --version）
   2.1.x 才有 .claude/rules/，更老的要退回 @import。
5. 你的系统？
   A) Windows    B) Linux / macOS
   —— 决定 7 道门里哪几道对你有意义（见 7.2）。
```

每个回答改变什么：

| 问题 | 答 A | 答 B |
|---|---|---|
| 1 | 直接写 `~/.claude/CLAUDE.md` | 先读现有文件，只追加缺的段，保留原文 |
| 2 | 装 `~/.claude/`，所有项目生效 | 装 `<项目>/.claude/`，并提示「`CLAUDE.local.md` 别进 git」 |
| 3 | 走第 6 节（两档都做） | 只走第 5 节，跳到第 8 节验收 |
| 4 | ≥2.1：用 `rules/` | <2.1：用 `CLAUDE.md` 里的 `@` 导入 |
| 5 | Windows：4 道可翻（A 类 3 道 + `unexpanded-temp-var`） | Linux/macOS：只有 A 类 3 道；其中 `ai-attribution` 建议用 `attribution.commit: ""` 代替，实际写 hook 的是 2 道 |

**用户答不上来时给默认值，但要说出来**：作用域默认用户级、门默认不装、版本让他跑 `claude --version`。

---

## 3. Claude Code 到底怎么加载规则（实测 2.1.306）

以下全部来自本机安装的 `claude.exe`（`@anthropic-ai/claude-code@2.1.306`）内嵌的说明文本，不是凭印象写的。

### 3.1 设置来源三层

`claude --setting-sources user,project,local` —— 官方参数说明原文：

> Comma-separated list of setting sources to load (user, project, local).

| 层 | 文件 | 进 git？ |
|---|---|---|
| user | `~/.claude/settings.json` | 否（跟人不跟仓库） |
| project | `<项目>/.claude/settings.json` | **是**，团队共享 |
| local | `<项目>/.claude/settings.local.json` | 否，必须写进 `.gitignore` |

### 3.2 `CLAUDE.md` 的层级（原文枚举）

二进制里的原文枚举，逐字：

> `.claude/CLAUDE.md` and `.claude/AGENTS.md`; `~/.claude/CLAUDE.md`; and, under both `.claude/` and `~/.claude/`, subfolders included, rule files (`rules/`), skills (`skills/*/SKILL.md`), custom commands (`commands/`), subagent definitions (`agents/`) and output styles (`output-styles/`).

另一处原文：

> the project file (`./CLAUDE.md`), the alternate project file (`./.claude/CLAUDE.md`), the local file (`./CLAUDE.local.md`), or any other loaded instruction file.

翻译成人话，加载顺序（从宽到窄，窄的覆盖宽的）：

| 层 | 路径 | 说明 |
|---|---|---|
| 用户级 | `~/.claude/CLAUDE.md` | 二进制里叫 "your user-level memory file"。**所有项目都加载** |
| 项目级 | `./CLAUDE.md` | 首选写法 |
| 项目级（别名） | `./.claude/CLAUDE.md` | 二选一，不是两个都写 |
| 项目级（别名） | `./.claude/AGENTS.md` | 同一个枚举里出现的，Codex 风格文件名也能被读 |
| 本地 | `./CLAUDE.local.md` | 个人覆盖，**必须 gitignore** |
| 政策 | managed-policy `CLAUDE.md` | 企业下发，改不动，别碰 |

外加两个目录，**递归加载**，`.claude/` 与 `~/.claude/` 下都算：

| 目录 | 内容 | 用法 |
|---|---|---|
| `rules/` | 规则文件（`rules/**`） | **分文件放规则，比塞进一个 CLAUDE.md 好维护** |
| `skills/*/SKILL.md` | 技能 | 目录名 = skill 名 |
| `commands/` | 自定义斜杠命令 | `/命令名` |
| `agents/` | 子代理定义 | frontmatter + prompt |
| `output-styles/` | 输出风格 | — |

### 3.3 `SKILL.md` 的硬要求

二进制里的校验原文：

> `Missing required "description" field in frontmatter`
> `name": names must not contain ":" (reserved for plugin namespacing)`

所以：

```yaml
---
name: dispatch                 # 必填，不能含 ":"，不能和目录名冲突
description: >-                # 必填，这是唯一的触发依据，写清楚「什么时候用」
  把一件有边界的活派给另一个 agent，并收证据。用于派活/开子代理/收工时。
---
正文……
```

`description` 是模型决定「要不要读这个 skill」的**唯一**输入。写成「一个关于派发的技能」等于没写。

### 3.4 `settings.json` 的关键键（本机实测值 + 通用含义）

本机 `~/.claude/settings.json` 全文 945 B，去掉插件和状态栏后，跟本协议相关的是这几个：

```json
{
  "attribution": { "commit": "", "pr": "", "sessionUrl": false },
  "permissions": { "allow": ["WebSearch", "WebFetch"], "defaultMode": "bypassPermissions" },
  "env": { "CLAUDE_CODE_EFFORT_LEVEL": "max" },
  "model": "opus",
  "fallbackModel": ["claude-opus-5-5", "claude-sonnet-5-5"],
  "alwaysThinkingEnabled": true,
  "effortLevel": "xhigh",
  "skipDangerousModePermissionPrompt": true
}
```

| 键 | 含义 | 跟本协议的关系 |
|---|---|---|
| `attribution.commit` / `.pr` | commit / PR 里加什么署名。空串 = 不加 | **`ai-attribution` 门的原生替代**，见附录 A |
| `permissions.deny` / `.allow` / `.ask` | 工具级规则，形如 `Bash(git commit *)` | 门的最便宜替代，见 7.3 |
| `permissions.defaultMode` | `bypassPermissions` = 不弹窗 | 注意：**不弹窗 ≠ 授权**，见 5.5 |
| `permissions.additionalDirectories` | 额外可访问目录 | 项目跨目录时用 |
| `hooks` | 见第 6、7 节 | **本机没装** |
| `disableAllHooks` | 布尔，一键停所有 hook | 装门之后的紧急开关 |
| `allowManagedHooksOnly` | 只跑政策下发的 hook | 企业环境用 |

本机这份配置里 **`hooks` 键不存在**——所以第 8 节的验收必须自己造证据，不能假设「本机能跑」。

### 3.5 三个静默失败陷阱

这三条会让人以为「装好了」，实际一行没生效。三者的**机制名是同一个：加载被静默旁路**——不是「加载出错」（那会报错），而是加载根本没发生，且没有任何提示。三种表现形态：校验失败整份丢弃 / 参数跳过 / 模式关闭。

**① hooks schema 不合法 → 整份 settings 被跳过。** 二进制原文：

> `"hooks"` (at the top level or under another key) — …
> `HOOKS_SCHEMA_INVALID`
> The managed settings document is not skipped for it, **unlike a user or project settings file**

也就是说：`~/.claude/settings.json` 里 `hooks` 写错一个字段，**整份 user settings 被丢弃**，你的 `permissions`、`model`、`env` 一起失效。而且 `claude -p` 模式下：

> Settings files that fail validation are **silently ignored** in this mode (no error dialog is shown).

⇒ **改完 settings 必须用 `claude` 交互模式启动一次看有没有报错**，不能只看 `-p` 的退出码。

**② `--bare` 跳过 hook 和 CLAUDE.md 自动发现。** 原文：

> `--bare` Minimal mode: skip hooks (those defined in settings and by installed plugins; …), … and CLAUDE.md auto-discovery.

⇒ 用 `--bare` 跑测试，规则和门**都不加载**。验收别加这个参数。

**③ `--safe-mode` 关掉全部定制。** 原文：

> `--safe-mode` Start with all customizations (CLAUDE.md, skills, installed plugins, hooks, MCP servers, custom commands and agents, …) disabled.

⇒ 用户报「规则没生效」时，先问是不是带了这个参数，或者环境变量 `CLAUDE_CODE_SAFE_MODE=1`。

---

## 4. 装什么：文件清单

装进目标作用域的东西只有三类，其余一律不装。

| 目标路径（用户级） | 来源（本仓库） | 必需？ |
|---|---|---|
| `~/.claude/CLAUDE.md` | 本文 5.1 的模板 | ✅ 最小安装 |
| `~/.claude/rules/agentrule/floor.md` | `library/floor/hard-floor.md` | ✅ 最小安装 |
| `~/.claude/rules/agentrule/incidents.md` | `library/floor/incidents.md` | 推荐 |
| `~/.claude/skills/dispatch/SKILL.md` | `library/dispatch/dispatch.md` 的派发段 | 推荐 |
| `~/.claude/skills/verify/SKILL.md` | 本仓库 `protocol/01-status.md` 的验收段 | 推荐 |
| `~/.claude/hooks/agentrule_gates.py` | 本文 6.2 | 只有完整安装 |
| `~/.claude/settings.json` | 合并本文 6.3 的片段 | 只有完整安装 |

**不装**：`plugins/`（58 MB，跟本协议无关）、`projects/`（会话转录，含隐私）、`sessions/*.key`（**密钥，永远不进仓库**）、`backups/`、`cache/`、`shell-snapshots/`。

---

## 5. 最小安装：只装规则，不装门

适用：用户答「不装门」，或机器上没有 Python，或版本 < 2.1 没有 `rules/`。
耗时约 10 分钟。**这一档装完，门一条都没有**——全靠模型读规则自觉，这是已知且明确的取舍，不是缺陷。

### 5.1 写 `~/.claude/CLAUDE.md`

这个文件**每次会话都进上下文**，所以只放铁律和入口，别放正文。二进制里对它的原话：

> CLAUDE.md is loaded into every Claude Code session, so it must be concise — only include what Claude would not otherwise know.

模板（约 45 行，直接复制，改掉 `<...>` 占位）：

```markdown
# 我的 agent 规则（AgentRule）

## 硬地板（摘录 5 条；全量以仓库里的 `library/floor/hard-floor.md` 为准）

1. 门说 no 就停，不许绕。**YOLO 只是不弹窗，不是额外授权。**
2. 临时目录外不许递归强删；删之前先记副本位置 + sha256。
3. 不许杀 `chrome` / `chromium` / `codex` / `claude` / `omp`——那是我的活会话。
4. 检查红了改代码，**不许改检查**。放松断言 / 删红的测试 / 补一行让它变绿，全禁。
5. 没跑过的事标 `[UNVERIFIED]`，不许说「完成了」。

## 入口

- 完整规则：`~/.claude/rules/agentrule/floor.md`（带执行层标记：门 / 停 / 提示）
- 事故档案：`~/.claude/rules/agentrule/incidents.md`
- 派发协议：`/dispatch`
- 收工前验收：`/verify`

## 我在什么档位

看本会话 system prompt 的 `Model:` 行：`deepseek-*` / `glm-*` 是 W 档（弱档），
`kimi-*` / `gpt-6-*` / `opus-*` 是 S 档（强档）。
W 档：先读 floor.md，再干活；S 档：直接干，踩到门再翻库。

## 判据

每条规则都要能回答「怎么知道违反了」。答不出来的，删掉——它只是装饰。
```

**不要**把 `hard-floor.md` 全文（19 KB）塞进 CLAUDE.md。实测口径：整目录 2,157 行常驻是净亏损，只在需要时打开。

### 5.2 放规则正文

**版本 ≥ 2.1：**

```bash
mkdir -p ~/.claude/rules/agentrule
cp library/floor/hard-floor.md  ~/.claude/rules/agentrule/floor.md
cp library/floor/incidents.md   ~/.claude/rules/agentrule/incidents.md
```

`rules/` 是递归加载的（二进制里是 `rules/**`），所以子目录随意分层。

**版本 < 2.1（没有 `rules/`）：** 在 `CLAUDE.md` 末尾加导入行，一行一个：

```markdown
@~/.claude/agentrule/floor.md
@~/.claude/agentrule/incidents.md
```

（`@` 导入是 `CLAUDE.md` 的原生语法，二进制里有 `@./CLAUDE.md` 的实例。路径写**正斜杠 + 引号**，见 5.6。）

### 5.3 装 skill

```bash
mkdir -p ~/.claude/skills/dispatch ~/.claude/skills/verify
# 正文必须复制，不许写成指向本机 omp 的指针（见 1.2）
# dispatch：正文取自 library/dispatch/dispatch.md，复制后按 3.3 补 frontmatter
cp library/dispatch/dispatch.md ~/.claude/skills/dispatch/SKILL.md
# verify：仓库没有单独一篇，用 protocol/01-status.md 的验收段 + dispatch.md 的收工段合成
```

复制完**必须**确认两件事：

```bash
head -5 ~/.claude/skills/dispatch/SKILL.md   # 必须是 --- 开头，含 name 和 description
grep -c '^name:' ~/.claude/skills/dispatch/SKILL.md   # 必须是 1
```

`name` 不能带 `:`（会跟插件命名空间冲突），`description` 必填（否则整条 skill 不加载）。

### 5.4 合并 settings（可选，但强烈建议）

最小安装**不需要**改 settings。如果用户已有 settings，只加这一条就能拿到 `ai-attribution` 门的等效效果：

```json
{ "attribution": { "commit": "", "pr": "", "sessionUrl": false } }
```

**用脚本合并，别手写覆盖整份文件**：

```bash
python - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.path.expanduser("~/.claude/settings.json"))
cfg = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
cfg.setdefault("attribution", {}).update({"commit": "", "pr": "", "sessionUrl": False})
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("merged:", p)
PY
```

### 5.5 「不装门」意味着什么

写清楚，别让用户以为装了安全边界：

- 模型**读得到**规则，但**没有任何东西强制它遵守**。规则是 guidance，不是 enforcement。
- `permissions.defaultMode: "bypassPermissions"` 意味着**连弹窗都没有**。YOLO 不弹窗，不等于多给了授权——它只是把「问你」这一步去掉了，该守的规矩一条没少。
- 真要拦，只有两条路：`permissions.deny`（粗粒度、声明式）或 `hooks`（细粒度、要写代码）。见第 6 节。

### 5.6 Windows 上的路径写法

会过 shell 的地方（hook 的 `command`、`statusLine.command`）**路径一律正斜杠 + 双引号**：

```json
"command": "python \"C:/Users/me/.claude/hooks/agentrule_gates.py\""
```

POSIX 层会吞掉没引号的反斜杠。这条在本机规则里是踩过坑的。

---

## 6. 完整安装：规则 + 门

在最小安装之上加两件事：一个门脚本，一段 `hooks` 配置。

### 6.1 先说清楚：门能覆盖什么、不能覆盖什么

本机 omp 的门是 **TypeScript 模块**（`~/.omp/agent/hooks/pre/guards.ts`），由 omp 进程直接调用，能拿到结构化参数、能返回结构化拒绝。Claude Code 的门是 **`settings.json` 里的一条 shell 命令**，从 stdin 读一段 JSON，用 stdout/退出码回答。两者**没有共用代码的可能**，只有「思想」可以搬。

一条 Claude Code 门能看到的全部输入（二进制里确认存在这些字段）：

```json
{
  "session_id": "…",
  "transcript_path": "…",
  "cwd": "…",
  "permission_mode": "…",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /tmp/x" }
}
```

它**看不到**：模型在想什么、上一轮发生了什么、文件内容（除非自己读）、你的看板状态。

它能回答的只有三种（二进制原文：`permissionDecision allow/deny/ask as for PreToolUse`）：

| 输出 | 效果 |
|---|---|
| `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}` | 拦下，理由回给模型 |
| 同上，`"allow"` | 放行，**跳过权限系统**（危险，别滥用） |
| 同上，`"ask"` | 转成问用户 |
| `exit 2` | 阻断（`exit code 2 (blocking error)`），stderr 回给模型 |
| `exit 0` + 无输出 | 不表态，走正常权限流程 |

### 6.2 门脚本

存成 `~/.claude/hooks/agentrule_gates.py`。**只用标准库，不装依赖。**

```python
#!/usr/bin/env python3
"""AgentRule gates for Claude Code (PreToolUse).

stdin  : hook JSON
stdout : decision JSON
自检   : python agentrule_gates.py --selftest
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile

# ---------- 路径工具 ----------

def _norm(p: str) -> str:
    p = os.path.expanduser(str(p).strip().strip("\"'"))
    try:
        p = os.path.realpath(p)
    except OSError:
        p = os.path.abspath(p)
    return os.path.normcase(p)


def _temp_roots() -> list[str]:
    cand = {tempfile.gettempdir(), os.environ.get("TMPDIR"),
            os.environ.get("TEMP"), os.environ.get("TMP")}
    return [r for r in (_norm(c) for c in cand if c) if r]


def _is_temp(path: str, roots: list[str]) -> bool:
    p = _norm(path)
    return any(p == r or p.startswith(r + os.sep) for r in roots)


# ---------- 门 1：临时目录外递归强删 ----------

_RM = re.compile(r"(?:^|[;&|]\s*|\bthen\s+|\bdo\s+)(?:sudo\s+)?rm\s+([^;&|]+)")
_PS_RM = re.compile(
    r"Remove-Item\b(?=[^;|]*-(?:Recurse|r)\b)(?=[^;|]*-(?:Force|fo)\b)", re.I)
_FLAG = re.compile(r"^-[A-Za-z]+$")


def _rm_targets(cmd: str) -> list[str] | None:
    """递归强删的目标；不是递归强删返回 None。"""
    if _PS_RM.search(cmd):
        return []          # PowerShell 形态：拿不到可靠路径就整条拒
    out: list[str] = []
    for m in _RM.finditer(cmd):
        tokens = m.group(1).split()
        flags = "".join(t[1:] for t in tokens if _FLAG.match(t))
        if "r" not in flags or "f" not in flags:
            continue
        for t in tokens:
            if _FLAG.match(t) or t == "--":
                continue
            out.append(t)
    return out or None


def gate_recursive_delete(cmd: str, roots: list[str]) -> str | None:
    targets = _rm_targets(cmd)
    if targets is None:
        return None
    if not targets:                                   # PowerShell 递归强删
        return "递归强删（PowerShell Remove-Item -Recurse -Force）一律拒绝：改用逐条删除"
    for t in targets:
        t = t.strip("\"'")
        if not t:
            continue
        if t.startswith(("$", "%")):                  # 未展开的变量，保守放行
            continue
        if _is_temp(t, roots):
            continue
        return f"临时目录外递归强删：{t}。先记副本位置 + sha256，再逐条删"
    return None


# ---------- 门 2：杀受保护进程 ----------

_KILL = re.compile(r"\b(kill|pkill|killall|taskkill|Stop-Process)\b", re.I)
_PROTECTED = ("chrome", "chromium", "codex", "claude", "omp")


def gate_protected_process(cmd: str) -> str | None:
    if not _KILL.search(cmd):
        return None
    low = cmd.lower()
    for name in _PROTECTED:
        if name in low:
            return f"不许杀 {name}：那是用户的活会话。要重启就先问用户"
    return None


# ---------- 门 3：commit 写 AI 署名 ----------

_ATTRIB = re.compile(
    r"(co-authored-by:\s*(claude|codex|gpt|copilot|ai)\b"
    r"|generated with\s*\[?claude"
    r"|claude\.ai/code"
    r"|🤖\s*generated)", re.I)


def gate_ai_attribution(cmd: str) -> str | None:
    if "git commit" not in cmd and "git merge" not in cmd:
        return None
    if _ATTRIB.search(cmd):
        return "commit 不许写 AI 署名。删掉 Co-Authored-By / Generated with 行再提交"
    return None


# ---------- 门 4：写入路径带字面 %TEMP% ----------

_LITERAL_TMP = re.compile(r"%(TEMP|TMP|TMPDIR)%", re.I)


def gate_temp_var(tool: str, tool_input: dict) -> str | None:
    if os.name != "nt":
        return None
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if path and _LITERAL_TMP.search(str(path)):
        return "写入路径带字面 %TEMP%：shell 不会展开它，会写成同级的怪目录。用 $env:TEMP"
    return None


# ---------- 汇总 ----------

def decide(payload: dict) -> str | None:
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    if not isinstance(ti, dict):
        return None

    if tool in ("Bash", "PowerShell"):
        cmd = str(ti.get("command") or "")
        if not cmd:
            return None
        roots = _temp_roots()
        for gate in (lambda: gate_recursive_delete(cmd, roots),
                     lambda: gate_protected_process(cmd),
                     lambda: gate_ai_attribution(cmd)):
            reason = gate()
            if reason:
                return reason
        return None

    if tool in ("Write", "Edit", "NotebookEdit", "MultiEdit"):
        return gate_temp_var(tool, ti)
    return None


def emit_deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))


# ---------- 自检 ----------

_TMP = os.path.join(tempfile.gettempdir(), "scratch")
_HOME = os.path.join(os.path.expanduser("~"), "repo")

FIXTURES = [
    (f"rm -rf {_HOME}",                        "deny",  "临时目录外递归强删"),
    (f"rm -rf {_TMP}",                         "allow", "临时目录内"),
    ("rm -f notes.txt",                        "allow", "非递归"),
    ("taskkill /F /IM chrome.exe",             "deny",  "受保护进程"),
    ("pkill -f codex",                         "deny",  "受保护进程"),
    ("kill 1234",                              "allow", "普通进程"),
    ('git commit -m "fix"',                    "allow", "无署名"),
    ('git commit -m "fix\n\nCo-Authored-By: Claude <noreply@anthropic.com>"',
                                               "deny",  "AI 署名"),
    ("Remove-Item -Recurse -Force C:\\x",      "deny",  "PowerShell 递归强删"),
    ("rm -rf \"$TMPDIR/x\"",                   "allow", "未展开的变量"),
]


def selftest() -> int:
    bad = 0
    total = len(FIXTURES) + 1
    for cmd, want, label in FIXTURES:
        got = "deny" if decide({"tool_name": "Bash", "tool_input": {"command": cmd}}) else "allow"
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {want:5} got={got:5}  {label}")
    path_case = decide({"tool_name": "Write",
                        "tool_input": {"file_path": "%TEMP%/x.txt"}})
    ok = (os.name != "nt") == (path_case is None)
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} temp-var  {path_case!r}")
    print(f"\n{total - bad}/{total} passed")
    return 1 if bad else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:                       # 坏输入：放行但留痕
        print(f"agentrule_gates: bad stdin: {exc}", file=sys.stderr)
        return 0
    reason = decide(payload)
    if reason:
        emit_deny(reason)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**关于「坏输入就放行」**：这是有意的 **fail-open**。理由——hook 读不到 JSON 时，Claude Code 本来就会走正常权限流程；在这里 `exit 2` 会让**每个**工具调用都被拒，等于把用户锁死。**fail-closed 只适用于「读到了、且判定危险」**。如果你要 fail-closed（例如生产环境），把 `except` 分支改成 `return 2`，并接受「hook 一坏全盘停」的代价。**选哪个必须告诉用户，不能替他选。**

### 6.3 配置 `hooks`

合并进 `~/.claude/settings.json`（**不要覆盖整份文件**）：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python \"C:/Users/me/.claude/hooks/agentrule_gates.py\"",
            "timeout": 20
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python \"C:/Users/me/.claude/hooks/agentrule_session.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

`matcher` 的语义（二进制原文）：

> The matcher is a string: a tool name (`"Bash"`), pipe-separated list (`"Edit|Write"`), or empty to match all.

合并脚本：

```bash
python - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.path.expanduser("~/.claude/settings.json"))
cfg = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
cmd = 'python "C:/Users/me/.claude/hooks/agentrule_gates.py"'   # ← 改成真实路径
entry = {"matcher": "Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit",
         "hooks": [{"type": "command", "command": cmd, "timeout": 20}]}
hooks = cfg.setdefault("hooks", {})
arr = hooks.setdefault("PreToolUse", [])
if not any(h.get("hooks", [{}])[0].get("command") == cmd for h in arr):
    arr.append(entry)
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
PY
python -m json.tool ~/.claude/settings.json > /dev/null && echo "JSON 合法"
```

### 6.4 `SessionStart` 注入口（可选，很值）

`SessionStart` 的输出支持 `additionalContext`（二进制原文：`hookEventName: "SessionStart", additionalContext: …`）。这让「规则常驻」从「塞满 CLAUDE.md」变成「每次开新会话注入一次」，省 token 也更好维护。

`~/.claude/hooks/agentrule_session.py`：

```python
#!/usr/bin/env python3
import json, os, sys

FLOOR = os.path.expanduser("~/.claude/rules/agentrule/floor.md")
LIMIT = 4000          # 字符；超了只给指针，别把 19 KB 全塞进去

def main() -> int:
    try:
        json.load(sys.stdin)
    except Exception:
        pass
    try:
        text = open(FLOOR, encoding="utf-8").read()
    except OSError:
        return 0
    if len(text) > LIMIT:
        text = (f"规则书在 {FLOOR}（{len(text)} 字符）。开头是硬地板；"
                f"干活前先读它，别凭记忆。")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": text,
    }}, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

### 6.5 完整安装的验收（必须真跑）

```bash
# ① 脚本自己能过
python ~/.claude/hooks/agentrule_gates.py --selftest
#   期望：11/11 passed，退出码 0

# ② 单条喂进去，看它真的拒绝
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash",
       "tool_input":{"command":"rm -rf /home/u/repo"}}' \
  | python ~/.claude/hooks/agentrule_gates.py
#   期望：输出 {"hookSpecificOutput":{...,"permissionDecision":"deny",...}}

# ③ settings 合法 + hook 真的挂上了
python -m json.tool ~/.claude/settings.json > /dev/null && echo "JSON ok"
python -c "import json,os;c=json.load(open(os.path.expanduser('~/.claude/settings.json')));
print([h['hooks'][0]['command'] for h in c['hooks']['PreToolUse']])"

# ④ 交互模式起一次，看有没有 settings 校验报错（-p 模式会静默吞掉）
claude
```

**④ 不能省。** 3.5 的陷阱①说的就是：schema 错了 `-p` 不报错，整份 settings 被丢。

---

## 7. hooks 不通用：7 道门怎么翻译

这是本文最重要的一节。**omp 的 7 道门不能复制到 Claude Code**，一行都不行。门的定义、语义与判定标准以 [`../protocol/03-gates.md`](../protocol/03-gates.md) 为准；本节只回答一件事：**哪几道能落到 Claude Code，落到哪里，代价是什么。**

### 7.1 两边机制对照

| | omp | Claude Code（2.1.306） |
|---|---|---|
| 门写在哪 | `~/.omp/agent/hooks/pre/guards.ts` | `settings.json` 的 `hooks` 键 |
| 语言 | TypeScript，编译进宿主进程 | **任意 shell 命令**（本机用 `python`） |
| 输入 | 结构化对象（工具名、参数、会话） | stdin 上的 JSON |
| 输出 | 返回值 / 抛异常 | stdout JSON 或退出码 |
| 拒绝语义 | 抛错，调用不执行 | `permissionDecision: "deny"` 或 `exit 2` |
| 事件 | pre/post 两类 | `PreToolUse` `PostToolUse` `UserPromptSubmit` `SessionStart` `SessionEnd` `Stop` `SubagentStop` `PreCompact` `Notification` |
| 匹配 | 代码里判 | `matcher` 字符串（工具名，`\|` 分隔） |
| 写错一个字段 | 一般抛错，看得见 | **整份 settings 被静默跳过**（`HOOKS_SCHEMA_INVALID`） |
| 能不能互相调用 | — | **不能。没有任何 shim。** |

一句话：**omp 的门是「进程内的函数」，Claude Code 的门是「一个会读 stdin 的外部程序」。** 前者能拿到的东西后者拿不到，后者要付的代价（进程启动、超时、跨平台 shell）前者不用付。

### 7.2 7 道门归三类

逐条比对容易看花眼。按**「这道门为什么存在」**分，7 道只有三类，每类一个机制名：

| 类 | 机制名 | 计数 | 门 | 在 Claude Code 上的处置 |
|---|---|---|---|---|
| A | **命令文本语义判定** | 3 | `ai-attribution` `recursive-delete` `protected-process` | ✅ 翻（用 6.2 的脚本） |
| B | **本机 shell 方言缺陷** | 3 | `unexpanded-temp-var` `nested-bash` `powershell-dollar` | ⚠️ 只翻 Windows 那一道 |
| C | **私有工具链耦合** | 1 | `board-write` | ❌ 不翻 |

合计 3 + 3 + 1 = **7**，与 `protocol/03-gates.md` 的条目数对得上。

**为什么这么分**，判据只有一句：**换一台 Linux 机器，这道门还有意义吗？**

- **A 类**的判据是命令本身的语义（删什么、杀什么、提交什么），跟宿主 shell 无关。Linux 上 `rm -rf` 一样危险，`kill` 一样能杀掉会话。
- **B 类**的判据是**这台机器 shell 层的缺陷**，不是协议要求：`%TEMP%` 是 cmd.exe 的变量语法；裸 `bash -c` 被劫持，是因为 PATH 里 `C:\Windows\System32\bash.exe`（WSL 启动器）压过 Git Bash；`$` 被吃掉，是因为 Git Bash 外层先做了一次展开。三条都只在「Windows + 多层 shell」下成立。
- **C 类**的判据是一个私有脚本的写保护规则，脱离那个脚本就不存在。

**抽样核对**（抽 4 条回原文验证归类，不是凭印象）：

| 抽检 | 原文里的判定依据 | 归类成立？ |
|---|---|---|
| `nested-bash` | 「Git Bash 会把裸 `bash -c` 劫持给 WSL 启动器（`C:\Windows\System32\bash.exe` 在 PATH 里压过它）」 | ✅ B 类：依据是 PATH 与宿主，不是命令语义 |
| `powershell-dollar` | 「外层 Git bash 会先吃掉 `$`」 | ✅ B 类：依据是 shell 嵌套层数 |
| `board-write` | 「`~/.owner/ops/board.md` 与 `ops/boards/*.md` 只追加；`board.py` 放行」 | ✅ C 类：依据是一个私有脚本 |
| `recursive-delete` | 「临时目录外递归强删」——**没有**任何 Windows 限定词 | ✅ A 类：依据是路径语义 |

四条全部落在预期类里，没有一条需要改类。逐条明细见附录 A。

**结论要这样讲给用户**：不是「装了 7 道门」，是「**7 道里 3 道跨平台该装、1 道 Windows 专属、3 道跟你无关**」。本机那 7 道之所以是 7 道，是因为那台机器真的发生过这 7 种事故，不是设计出来的。换一台机器，门的数量本来就应该变——**门的数量是事故的计数，不是能力的计数**。

### 7.3 更便宜的替代：先用 `permissions.deny`

在写代码之前，先问「声明式能不能覆盖」。`permissions.deny` 零代码、零超时、不会被 schema 校验丢掉：

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~*)",
      "Bash(taskkill /F /IM chrome*)",
      "Bash(pkill -f codex)"
    ]
  }
}
```

能力边界：**只能匹配命令字符串的形状，不能判路径是不是在临时目录里，不能看文件内容。** 所以它拦得住「典型写法」，拦不住「换个写法」。作为第一层够用；要判语义还得上 hook。

**两层一起装是对的**：`deny` 挡掉 90% 的手滑，hook 处理剩下需要判断的。

### 7.4 装门的三个代价（要主动告诉用户）

1. **每次工具调用起一个进程。** 本机 Python 启动约 30–80 ms；一个会话几百次工具调用，累计是秒级。嫌慢就把 `matcher` 收窄（只留 `Bash`）。
2. **schema 一错，整份 settings 失效**（3.5 陷阱①）。所以装完必须交互模式起一次。
3. **门会误伤。** 例如用户真想 `rm -rf ./build`——按第 2 道门这是「临时目录外」，会被拒。**这是设计意图**（先记副本再删），但必须提前说明，否则用户第一次撞门就以为坏了。

### 7.5 如果你决定不装门

完全正当，而且对多数人是对的选择。前提是把话说明白：

> 装了规则 = 模型知道该怎么做。装了门 = 模型做不到的时候会被拦住。**这两件事不一样。**
> 本仓库的规则书自己就写着：「这里没有任何安全边界——它是给人读的指导（guidance），不是强制执行（enforcement）。」

不装门时，至少装 `attribution.commit: ""` 和几条 `permissions.deny`——它们零成本，且不依赖任何脚本。

---

## 8. 验收：怎么证明「装对了」

**每条都要能跑，跑不出结果的验收不算验收。**

### 8.1 最小安装

```bash
# ① 文件在位
test -f ~/.claude/CLAUDE.md && echo "CLAUDE.md ok"
test -d ~/.claude/rules/agentrule && ls ~/.claude/rules/agentrule/

# ② skill 的 frontmatter 合法（缺 description = 整条不加载）
python - <<'PY'
import glob, sys
bad = 0
for f in glob.glob(__import__("os").path.expanduser("~/.claude/skills/*/SKILL.md")):
    head = open(f, encoding="utf-8").read(800)
    if not head.startswith("---"):
        print("FAIL 无 frontmatter:", f); bad += 1; continue
    fm = head.split("---")[1]
    for key in ("name:", "description:"):
        if key not in fm:
            print(f"FAIL 缺 {key}:", f); bad += 1
print("skills:", "ok" if not bad else f"{bad} 个问题")
sys.exit(1 if bad else 0)
PY
```

**③ 哨兵验证（证明规则真的进了上下文）。** 在 `CLAUDE.md` 里放一行哨兵，然后问模型：

```bash
# 先在 CLAUDE.md 末尾加一行：
#   <!-- AR-SENTINEL: 7f3a91 -->
claude -p "只输出你 user memory 里 AR-SENTINEL 后面那串字符，不要解释。"
# 期望输出包含：7f3a91
# 输出别的东西 = CLAUDE.md 没加载 → 查 3.5 的三个陷阱
```

这是唯一能证明「加载了」而不只是「文件存在」的检查。**别用「问模型你有哪些规则」这种题**——模型会编。

### 8.2 完整安装

在 8.1 之上：

```bash
# ④ 门脚本自检
python ~/.claude/hooks/agentrule_gates.py --selftest
# 期望：11/11 passed

# ⑤ 门真的在拦（行为验收，不是文件验收）
#    注意：payload 里故意不放 chrome / codex 这些名字——否则你自己那条
#    protected-process 门会把「这条测试命令」拦掉，测试永远跑不起来。
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash",
  "tool_input":{"command":"rm -rf ~/agentrule-should-not-exist"}}' \
  | python ~/.claude/hooks/agentrule_gates.py | grep -q '"deny"' && echo "门在工作"

# ⑥ settings 合法
python -m json.tool ~/.claude/settings.json > /dev/null && echo "JSON ok"

# ⑦ 交互模式起一次（唯一能看见 schema 报错的方式）
claude
```

**⑧ 端到端（可选，要花 token；本机未跑通）**：让 Claude Code 真的去执行一条该被拒的命令。用**不存在**的路径，门失效也删不到东西：

```bash
claude -p "用 Bash 工具执行：rm -rf ~/agentrule-should-not-exist" --allowedTools "Bash"
# 期望：模型报告被拒（permissionDecision: deny）
# 若它真的执行了 = 门没挂上 → 回 6.3 和 3.5 陷阱①
```

本机实测：这条**跑不通，但不是门的问题**——`claude -p` 在本 shell 返回 `terminal_reason: "api_error"`、`input_tokens: 0`，即当前环境没有可用的 API 凭据。所以 ⑧ 标 `[UNVERIFIED]`。

同一条限制也打掉另外两条：**8.1 的 ③（哨兵，要模型回答）**和**8.2 的 ⑦（交互式 `claude`，要 TTY）**，本机都没跑，同样标 `[UNVERIFIED]`。**不需要模型、不需要 TTY 的检查（8.1 ① ②、8.2 ④ ⑤ ⑥）全部实跑通过**，逐条结果见第 11 节。

---

## 9. 回滚

装之前**先备份**，回滚才有东西可回：

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.before-agentrule-$(date +%Y%m%d)
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.before-agentrule-$(date +%Y%m%d)
```

回滚三种粒度：

| 目标 | 动作 |
|---|---|
| 只停门，留规则 | settings 里加 `"disableAllHooks": true`（不用删配置） |
| 停门 + 停规则 | 删 `hooks` 键 + 删 `CLAUDE.md`（或恢复备份） |
| 全退 | 恢复两个 `.before-agentrule-*` 备份，删 `~/.claude/rules/agentrule/`、`~/.claude/hooks/`、装进去的 skill 目录 |

**回滚后必须重跑 8.1 的 ③**，确认哨兵读不到了——否则你只是以为回滚了。

---

## 10. 本文不覆盖什么

- **Codex 的装法**：看 [`codex.md`](codex.md)。它的规则入口是 `AGENTS.md` + `config.toml`，跟本文不同。
- **omp 的装法**：看 [`omp.md`](omp.md)。7 道门的原始实现在那里。
- **协议本身**：看 [`../protocol/00-floor.md`](../protocol/00-floor.md)。本文只讲 Claude Code 这一个落点。
- **企业 policy / managed settings**：本文只处理 user / project / local 三层。
- **插件**：`plugins/` 那 58 MB 跟本协议无关，一个字都没讲。
- **非 2.1.x 的完整支持**：`rules/` 目录是 2.1 才有；更老版本只能靠 `CLAUDE.md` 的 `@` 导入，`SessionStart` 的 `additionalContext` 也可能没有。

---

## 11. 验收判据（本文自己）

判据原文（逐字）：**「文件存在 >3 KB，含实测目录清单 + 两档步骤 + hooks 不通用说明。」**

| 词 | 可判？ | 怎么判 |
|---|---|---|
| 文件存在 | ✅ 可判 | `test -f adapters/claude-code.md` |
| `>3 KB` | ✅ 可判 | `wc -c < adapters/claude-code.md` |
| 实测目录清单 | ✅ 可判 | 第 1 节；每个条目都能在 1.3 的命令输出里找到，大小/文件数逐项对得上 |
| 两档步骤 | ✅ 可判 | 第 5 节（最小）、第 6 节（完整），各自是可复制的命令序列，不是建议 |
| hooks 不通用说明 | ✅ 可判 | 第 7 节：机制对照表 + 三类归并 + 明确写「没有任何 shim」；逐条在附录 A |

**边界线（会翻转判定的那一行）**：如果第 5 节和第 6 节退化成「你可以考虑这样组织规则」这类描述，而没有可执行的命令与期望输出，那么「两档步骤」这一项就不成立，整份判定翻成不合格。本文当前的写法是可执行的，所以不翻。

**没证明的部分**：凡是需要模型调用或交互式 TTY 的检查，本机都跑不了——当前 shell 里 `claude -p` 返回 `terminal_reason: "api_error"`、`input_tokens: 0`。具体是 8.1 ③（哨兵）、8.2 ⑦（交互启动）、8.2 ⑧（端到端），三条都标 `[UNVERIFIED]`。

**证明过的部分**（本机 2026-11-02 实跑，原样输出）：

| 检查 | 命令要点 | 实测输出 | 退出码 |
|---|---|---|---|
| 门脚本自检 | `python agentrule_gates.py --selftest` | `11/11 passed` | 0 |
| 拒绝：递归强删 | stdin 喂 `rm -rf /home/u/repo` | `{"…","permissionDecision":"deny","permissionDecisionReason":"临时目录外递归强删：/home/u/repo…"}` | 0 |
| 拒绝：受保护进程 | stdin 喂 `taskkill /F /IM chrome.exe` | `{"…","permissionDecision":"deny",…"不许杀 chrome…"}` | 0 |
| 放行：干净命令 | stdin 喂 `ls -la` | 无输出 | 0 |
| skill frontmatter（正例） | 本机 2 个 skill | `skills: ok` | 0 |
| skill frontmatter（反例） | 故意缺 `description` | `FAIL 缺 description: …` | **1** |
| 8.1 ① | `test -f ~/.claude/CLAUDE.md` | 无输出（本机确实没有该文件） | 1 |
| 8.2 ⑤ | 原文命令 | `门在工作` | 0 |
| 8.2 ⑥ | `python -m json.tool ~/.claude/settings.json` | `JSON ok` | 0 |

反例那一行是关键：**检查器在应该红的时候真的红了**。一个永远绿的检查器比没有检查更糟。

另外，本文第 6.2 节的代码块与实跑通过的脚本做过逐字节比对（`shipped == tested: True`），所以文档里贴的就是跑过的那份，不是另抄一份。

---

## 附录 A：7 道门逐条判定

正文只放类（7.2），逐条明细在这里。判据列写的是「为什么它属于那一类」，不是复述规则。

| # | 门 | 语义 | 类 | 处置 | 理由 / 落点 |
|---|---|---|---|---|---|
| 1 | `ai-attribution` | commit 不写 AI 署名 | A | ✅ 翻，但有更省的办法 | `settings.json` 的 `attribution.commit: ""` 直接关掉署名生成，比 hook 可靠；hook 只在「模型手写 Co-Authored-By」时兜底。两道一起上 |
| 2 | `recursive-delete` | 临时目录外递归强删 | A | ✅ 翻 | 跨平台有效，也是最高频的一道（本机 402 次命中里占 21.2%）。落在 6.2 的 `gate_recursive_delete` |
| 3 | `protected-process` | 不许杀 `chrome` / `chromium` / `codex` / `omp` | A | ✅ 翻 | 跨平台有效。落点 `gate_protected_process`，名单里额外加了 `claude` |
| 4 | `unexpanded-temp-var` | 写入路径带字面 `%TEMP%` / `%TMP%` / `%TMPDIR%` | B | ⚠️ 只有 Windows 翻 | `%TEMP%` 是 cmd.exe 语法。Linux/macOS 上它只是个怪文件名，不构成事故。脚本里用 `os.name == "nt"` 直接短路 |
| 5 | `board-write` | 看板文件只追加 | C | ❌ 不翻 | 依赖私有 `board.py` 与 `ops/board.md`。开源用户没有这套东西，翻了是空转 |
| 6 | `nested-bash` | 裸 `bash -c` / `bash -lc` | B | ❌ 不该翻 | 本机 PATH 里 WSL 的 `bash.exe` 压过 Git Bash 造成的**本地事故**。Linux 上 `bash -c` 完全正常，翻了会误伤 |
| 7 | `powershell-dollar` | `powershell -Command` 带 `$` | B | ❌ 不该翻 | Windows + Git Bash 双层引号才有的问题。Linux/macOS 没有 powershell |

**读这张表的正确方式**：第 5、6、7 行的「不翻」不是偷懒，是**那三道门的成因在你的机器上不存在**。装一个永远不触发的门，比不装更糟——它给你一种「有保护」的错觉，还多花每次工具调用的进程启动时间。

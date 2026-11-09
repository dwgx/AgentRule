<!-- measured on omp/18.14.1, Windows, 2026-11-02; every number below is reproducible with the command next to it -->
# 在 omp 上安装这套规则

> EN: Which files omp actually reads, which two to write first, and the command that proves each one took effect.

**一句话**：omp 上装这套规则 = 写 **2 个 markdown 文件**（`RULES.md` + `AGENTS.md`）；想让规则**拦得住**（而不是只写在上下文里），再加 **1 个 TS 文件**（`hooks/pre/guards.ts`）。三样都不联网、不编译、不用装 bun。

本文所有路径、大小、输出都是在一台 Windows 机器上**实测**的（`omp/18.14.1`，2026-11-02）。每条断言后面给了复跑命令。

---

## 0 · 先问，再动手

装之前必须问用户这四件事。**猜错会写到错的地方，或者把用户已有的规则盖掉。**

| # | 问题 | 为什么问 | 不知道时的默认 |
|---|---|---|---|
| 1 | 装给谁：这台机器的**默认 profile**，还是某个 `--profile <name>`？ | `--profile` 会把整个 agent 目录换成 `~/.omp/profiles/<name>/agent`；`PI_CODING_AGENT_DIR` 也能换 | 默认 profile：`~/.omp/agent` |
| 2 | `~/.omp/agent/RULES.md` 或 `AGENTS.md` **已经存在吗**？ | 存在就是别人的规则，只能合并，不能整份覆盖 | 先 `ls -l` 看一眼再决定 |
| 3 | 要不要 **hooks**（能拦命令的代码门）？ | 它是**代码**，跑在用户进程里，写错会挡住正常干活 | 先装档 A，问过再上档 B |
| 4 | 规则库放哪（clone 到哪个目录）？ | `RULES.md` 里的入口路径要写绝对路径 | 建议 `~/agentrule`，不要放进 `.omp/agent`（那是配置目录，不是仓库） |

问完再动。写之前对已有文件做备份：同目录 `*.before-<topic>-<date>`（真日期），并把「一行恢复命令」写在旁边。

---

## 1 · omp 的配置面（实测）

### 1.1 目录长什么样

```console
$ omp --version
omp/18.14.1

$ ls -1 ~/.omp/agent | wc -l
94

$ ls -l ~/.omp/agent/*.md
-rwxrwxrwx 1 somebody somegroup 4427 Oct 30 19:39 AGENTS.md
-rwxrwxrwx 1 somebody somegroup 6855 Nov  2 07:31 RULES.md
-rwxrwxrwx 1 somebody somegroup 1483 Oct 15 23:28 TITLE_SYSTEM.md

$ ls -1 ~/.omp/agent/hooks/pre/*.ts ~/.omp/agent/hooks/post/*.ts
~/.omp/agent/hooks/pre/guards.ts
~/.omp/agent/hooks/pre/idle-count.ts
~/.omp/agent/hooks/post/ctx-watch.ts
~/.omp/agent/hooks/post/log-bash.ts
~/.omp/agent/hooks/post/log-mcp.ts
~/.omp/agent/hooks/post/recover-pointer.ts
~/.omp/agent/hooks/post/tier-card.ts

$ ls -1 ~/.omp/agent/skills | wc -l
17
```

94 个顶层条目里，**真正是配置的只有 8 类**，其余是运行时数据（`sessions/` `blobs/` `cache/` `agent.db`）和历史备份（`*.bak-*` `*.before-*`）。别被数量吓到。

| 条目 | 是什么 | 要不要动 |
|---|---|---|
| `RULES.md` | sticky 规则，**每请求全文注入** | **档 A 要写** |
| `AGENTS.md` | 用户级 context file | **档 A 要写** |
| `hooks/pre/*.ts`、`hooks/post/*.ts` | 代码门，启动时被 import | **档 B 要写** |
| `skills/<name>/SKILL.md` | 技能包（一层目录，不递归） | 档 A+ 可选 |
| `config.yml` | 设置（`skills.enabled` / `tools.approvalMode` / `disabledProviders` …） | 一般不动 |
| `models.yml` | 模型注册表 | **不要动**（和规则无关） |
| `agents/*.md` | 子代理角色定义（本机 9 份） | 可选，本文不覆盖 |
| `TITLE_SYSTEM.md` | 会话标题生成的 system prompt | 不动 |
| `mcp.json` / `settings.json` / `.env` | MCP、少量设置、环境变量 | 不动 |

### 1.2 每个文件的作用与加载时机

| 文件 | 机制 | 什么时候从磁盘读 | 每轮都在提示词里？ | 子代理拿得到？ |
|---|---|---|---|---|
| `AGENTS.md` | context file（`<repo-rules>` 块） | 会话开始 | 是 | **不**（按文件名过滤掉） |
| `RULES.md` | sticky rule（`alwaysApply`，名字 `RULES`） | 会话开始 + `/clear`、`/new` | **是，全文，每个请求** | **是** |
| `skills/<n>/SKILL.md` | skill | 会话开始 | 只列 `name` + `description`；正文按需 `read` | 是（继承父会话） |
| `hooks/pre/*.ts`、`hooks/post/*.ts` | extension factory | **进程启动**时 import | 否（是代码不是文本） | 是（父会话的 factory 被 rebind） |
| `config.yml` | settings | 启动 | 否 | — |
| `agents/*.md` | task agent 定义 | 派发子代理时 | 否 | — |

三条容易记错的：

1. **`RULES.md` 是 sticky**：frontmatter 改不掉；只要文件在 `~/.omp/agent/` 或最近的 `<repo>/.omp/`，它的**全文**就跟着每一个请求走。改完不用重启，`/clear` 或 `/new` 就重读。
2. **`AGENTS.md` 不进子代理**。你希望子代理也守的规矩，只能写进 `RULES.md`。
3. **hooks 是启动时 import 的**。改完必须**重启 omp**（新开一个进程）。在 Windows 上原地改文件不会被重新加载——omp 的 reload 靠 `?mtime` 查询串，Bun 在 Windows 上忽略它。

### 1.3 实测：RULES.md 每轮要花多少钱

```console
$ cd ~/.omp/agent && wc -c RULES.md && omp toks RULES.md
6855 RULES.md
size   6.7KB · 3,808 chars · 52 lines

encoding          models                    tokens  chars/tok
o200k_base        GPT-4o · o1 · GPT-5+       2,174       1.75
cl100k_base       GPT-3.5 · GPT-4            2,685       1.42
claude-v5         Claude 5+                  3,082       1.23
```

**6.7 KB ≈ 2.2k tokens，每个请求都付一次。** 所以 `RULES.md` 要短：只放**铁律 + 入口**，方法、案例、模板全部放仓库，用到再开（`library/`）。`AGENTS.md` 同理（本机 4,427 B ≈ 1,395 tokens），但它只在开场注入一次。

### 1.4 四个实测事实（决定了下面怎么装）

**(a) `RULES.md` 进系统提示，`AGENTS.md` 进项目上下文块。** 用 RPC 的 `get_state` 把提示词原样拉出来对比：

```console
$ printf '%s\n' '{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --cwd . 2>/dev/null | grep -c "写在上下文里 ≠ 被执行"
1
$ printf '%s\n' '{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --no-rules --cwd . 2>/dev/null | grep -c "写在上下文里 ≠ 被执行"
0
```

同一次实验里，带规则 `systemPrompt` 共 **19,589** 字符，`--no-rules` 是 **15,756**，差 **3,833**——正好是 `RULES.md` 的正文（3,808 字符）。`AGENTS.md` 在另一个块里（`<project-context>` → `<repo-rules>` → `<file path="…AGENTS.md">`）。

**(b) 子代理拿 `RULES.md`，不拿 `AGENTS.md`。** 子代理的会话文件里有 `session_init.systemPrompt`（主会话没有），可以直接查：

```console
$ python -c "import json,sys; [print(len('\n'.join(o['systemPrompt'])), '你的档位' in '\n'.join(o['systemPrompt'])) for o in map(json.loads, open(sys.argv[1],encoding='utf-8')) if o.get('type')=='session_init']" \
    ~/.omp/agent/sessions/<bucket>/<stem>/<ChildName>.jsonl
20967 True
```

同一份提示词里搜不到 `AGENTS.md` 的第一行。**结论：给子代理的规矩写 `RULES.md`。**

**(c) hooks 自动发现，不需要装 bun，也不需要改配置。** 放一个小 factory（只 `pi.registerCommand`）进项目目录，用受限 `PATH`（去掉 bun）跑：

```console
$ printf '%s\n' '{"id":"1","type":"get_state"}' | PATH="C:/Windows/System32;C:/Users/<you>/AppData/Local/omp" omp --mode rpc --no-session --cwd . | grep -c probe-xyz
1
```

`probe-xyz` 是那个 hook 用 `pi.registerCommand` 注册的命令——说明 `.ts` 被 omp 自己的运行时 import 了，没有外部 `bun` 参与。

**(d) 加载失败看得见，加载成功是静默的。** 故意放一个语法错的 hook：

```console
$ printf '%s\n' '{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --hook ./broken.ts 2>&1 >/dev/null
Failed to load extension ~/probe/broken.ts: Failed to load extension: Failed to parse extension source for dependency rewriting: …
```

所以「装好了」的判据是 **stderr 一行都没有**，不是看到什么成功提示。

---

## 2 · 档 A：最小可用（只放规则，2 个文件）

目标：让规则**进上下文**。做不到拦截，但已经能改变行为，且零风险、零依赖。

### 2.1 要建的文件

| 目标路径 | 内容从哪来 | 大小参考 |
|---|---|---|
| `~/.omp/agent/RULES.md` | 用 §2.2 的模板，`{{REPO}}` 换成仓库绝对路径 | 目标 ≤ 60 行 / ≤ 2k tokens |
| `~/.omp/agent/AGENTS.md` | 用 §2.3 的模板 | 目标 ≤ 40 行 |

两个模板里有两处占位符要换：`{{REPO}}` = 规则库的绝对路径，`{{HARNESS}}` = 你的 harness 名（这里填 `omp`）。

项目级替代（**二选一，别同时装**）：`<repo>/.omp/RULES.md` 和 `<repo>/.omp/AGENTS.md`。注意 omp 只认**从 cwd 往上走遇到的第一个非空 `.omp/`**；那个目录里没有 `RULES.md` 就**不会**继续往上找。

### 2.2 `RULES.md` 模板（复制，改 `{{REPO}}`）

```markdown
# 硬地板

你是 agent。这页只留不许做的事；方法在 `{{REPO}}/library/`，用到哪篇开哪篇，别整目录预读。

## 四条停点
1. 毁数据：删除、覆盖、清回收站 —— 先记副本路径 + sha256，单独报备。
2. 花钱：计费调用、更贵的模型档 —— 先问。
3. 停服务：杀进程、停端口、改远端 —— 先判依赖，单独点名。
4. 两种读法差很远 —— 停下来问，不许猜。

## 十条不许
- 没跑过就说完成 / 没跑过却不标 `[UNVERIFIED]`。
- 检查红了去改检查（放松断言、删红的测试、改门判据）。
- commit 里写 AI 署名（`Co-Authored-By` 一类）。
- 递归强删临时目录以外的东西。
- 杀浏览器或你自己的 harness 进程。
- 把凭据写进任何仓库、报告、看板。
- 没点名就改别人的配置或项目树。
- 只写「0 命中 / 没有 / 全清」，不附范围命令。
- 空转：`sleep`、轮询、拿查 job 当心跳。
- 整份读 transcript；绕过工具用内联 shell。

## 三条做法
- 先一句话复述目标再动手；完成条件要能跑一条命令或看一个文件。
- 只改点名的；顺手改旁边 = 事故。
- 先写结论，判断带证据；不确定就写不确定。

## 档位（W / S）
看会话 system prompt 的 `Model:` 行：`deepseek-*` / `glm-*` 是 **W（弱档）**，`kimi-*` / `gpt-6-*` / `opus-*` 是 **S（强档）**。
- W 档顺序：① `{{REPO}}/library/floor/incidents.md` §一 ② `{{REPO}}/library/recovery/work.md` §做成 ③ `{{REPO}}/library/dispatch/dispatch.md` 的 brief 模板 ④ 派活/交活前开 `{{REPO}}/library/dispatch/cards.md`，把对应的卡粘进 brief。
- S 档：直接干。只在**门拦下来**或**两种读法差很远**时再开库页。
- 两档都不跳：门拦下来就改代码；`STATUS:` 首行；`DONE WHEN` 能跑一条命令。

## 入口
- 事故档案（为什么有这些规矩）：`{{REPO}}/library/floor/incidents.md`
- 派发协议：`{{REPO}}/library/dispatch/dispatch.md`
- 压缩/重启后接上：`{{REPO}}/library/recovery/recovery.md`
```

为什么是这个形状：这页**每个请求都付费**（§1.3 实测 2.2k tokens），所以只放「不许」和「去哪找」。不要往里塞案例和模板——那是 `library/` 的活。

### 2.3 `AGENTS.md` 模板

```markdown
# 你是谁

你是 {{HARNESS}}（这里是 omp）。跟当前项目的 `AGENTS.md`；仓库根若有 `CLAUDE.md` 一并遵守。
对用户：中文。代码和 git 用英文。先写结论，判断带证据。

# 规则在哪

- 每轮硬地板：`~/.omp/agent/RULES.md`（sticky，已经注入，**不要在这里重复抄一遍**）。
- 库：`{{REPO}}/library/`。不要整目录预读，用到哪篇开哪篇。
- 入口：`{{REPO}}/README.md`、`{{REPO}}/protocol/README.md`。

# 先做

1. 一句话复述要做成什么样，再动手；完成条件要能跑一条命令。
2. 点位清楚就自己做到完；毁数据 / 花钱 / 停服务 / 两种读法差很远才停。
3. 写最少，只改点名的。跑过再交；没跑过标 `[UNVERIFIED]`。

# 子代理

- 子代理**拿不到这份文件**，只拿 `RULES.md`。要子代理守的规矩写进 `RULES.md`。
- 派发前开 `{{REPO}}/library/dispatch/dispatch.md` 的 brief 模板。

# 压缩之后

- 按 `{{REPO}}/library/recovery/recovery.md`：先复述一行（原话要什么 / 还开着什么 / 下一步），只补一个缺口。
- 压缩摘要是模型写的，可能改写任务；和盘上事实冲突时以盘上为准。
```

### 2.4 装

```bash
# Git Bash / macOS / Linux
mkdir -p ~/.omp/agent
for f in RULES.md AGENTS.md; do
  if [ -f "$HOME/.omp/agent/$f" ]; then
    cp "$HOME/.omp/agent/$f" "$HOME/.omp/agent/$f.before-agentrule-$(date +%Y%m%d)"
  fi
done
# 然后把 §2.2 / §2.3 的内容写进去（用你的编辑工具，不要用 cat 覆盖已有文件）
```

```powershell
# PowerShell
New-Item -ItemType Directory -Force "$HOME\.omp\agent" | Out-Null
if (Test-Path "$HOME\.omp\agent\RULES.md")  { Copy-Item "$HOME\.omp\agent\RULES.md"  "$HOME\.omp\agent\RULES.md.before-agentrule-$(Get-Date -f yyyyMMdd)" }
if (Test-Path "$HOME\.omp\agent\AGENTS.md") { Copy-Item "$HOME\.omp\agent\AGENTS.md" "$HOME\.omp\agent\AGENTS.md.before-agentrule-$(Get-Date -f yyyyMMdd)" }
```

两个文件都写完，**不用重启**——下一个会话开始就生效。

### 2.5 验收（两条，都免费）

**V1 文件在位：**

```bash
ls -l ~/.omp/agent/RULES.md ~/.omp/agent/AGENTS.md
# 期望：两个文件都在，字节数 > 0
```

**V2 规则真的进了系统提示（决定性）：**

```bash
printf '%s\n' '{"id":"1","type":"get_state"}' \
  | omp --mode rpc --no-session --cwd "$PWD" 2>/dev/null \
  | grep -c "写在上下文里 ≠ 被执行" || true
# 期望 ≥1。把 --no-rules 加上重跑，期望 0 —— 这才证明是 RULES.md 带进去的。
```

```powershell
# PowerShell 5.1：中文模式匹配不可靠（实测恒 0，见下），改比长度
$a = ('{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --cwd $PWD | Out-String).Length
$b = ('{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --no-rules --cwd $PWD | Out-String).Length
"with=$a without=$b delta=$($a-$b)"   # 期望 delta > 3000（本机实测 6,966）
```

> - `grep -c` 数到 0 会返回退出码 1，所以带 `|| true`。
> - `omp read rule://RULES` 在**会话外**会回 `Unknown rule: RULES`——那是正常现象（外部命令不建会话规则表），**不是装失败**。
> - **PS 5.1 的假阴性**：它按控制台代码页解码原生输出，`Select-String '你的档位'` 实测恒为 0（ASCII 模式如 `UNVERIFIED` 却能命中 1）。所以 Windows 上优先用 Git Bash 跑上面那条；非用 PowerShell 就比长度。
> - 别拿 `[UNVERIFIED]` 当标记：它同时出现在 `AGENTS.md` 里，`--no-rules` 也会命中（实测 1 vs 1），证明不了是 `RULES.md` 带进去的。

---

## 3 · 档 A+：加 skills（可选，纯 markdown）

omp 的 skill 是「按需打开的说明书」：启动时只把 `name` + `description` 放进提示词，正文用 `read skill://<name>` 取。适合把「验证」「派发」「收工」这类**有固定步骤**的东西固化。

### 3.1 放哪、怎么写

```
~/.omp/agent/skills/<name>/SKILL.md
```

- **一层目录，不递归**：`skills/group/<name>/SKILL.md` 不会被发现。
- frontmatter 至少要有 `name` 和 `description`（native 提供方要求 `description`，缺了不加载）。
- `description` 是路由：写「什么时候用」，不是「包含什么」。

```markdown
---
name: verify
description: >
  Use when about to say 完成了 / 修好了 / 验证, or when the task says 证明它,
  after any code, config, hook or skill change; symptom: no single decisive
  command has been named and run, or the only evidence is a paraphrase.
metadata:
  version: 1
  last-reviewed: 2026-11-02
---

# Verify

1. 说出那条能一票定案的命令。别的都不算。
2. 跑它。原样贴出决定性的一行：`exit=` 码、命中的日志行、拦截理由。
3. 改已有文件之前，先留 `<file>.before-<topic>-<date>`，并在证据旁边写一行恢复命令。
```

建议先只装 3 个：`verify`、`dispatch`、`shougong`（对应 `library/tooling/skills.md` 的路由表）。**别一次装 17 个**——每个的 `description` 都常驻提示词。

### 3.2 验收

```bash
omp read skill://verify/SKILL.md | head -3
# 期望：第一行是 [~/.omp/agent/skills/verify/SKILL.md#XXXX]，然后 frontmatter
```

```bash
printf '%s\n' '{"id":"1","type":"get_state"}' | omp --mode rpc --no-session --cwd "$PWD" 2>/dev/null \
  | grep -c '"name":"skill:verify"'
# 期望 1 —— skill 被注册成了 /skill:verify 命令
```

> 实测坑：`omp read skill://<name>` 走外部命令路径时**只认用户级** skill；项目级 `<repo>/.omp/skills/` 的 skill 在会话里能被发现（`skill:<name>` 命令在），但外部 `read` 可能报 `Unknown skill`。用上面第二条验收项目级 skill。

---

## 4 · 档 B：完整（加 hooks）

目标：把「写在上下文里」变成「拦得住」。`RULES.md` 里写「不许」，hook 里是**代码拒绝**。

### 4.1 要建的文件

| 目标路径 | 说明 |
|---|---|
| `~/.omp/agent/hooks/pre/guards.ts` | §4.2 的全文，**一个文件，无依赖** |
| `~/.omp/agent/hooks/log/` | 运行时自动建；拦截记录写这里 |

不需要改 `config.yml`，不需要 `package.json`，不需要装 bun（§1.4c）。

### 4.2 `guards.ts`（5 道门，全文）

> 装之前**把全文给用户看一遍**。它是代码，会在每次工具调用前跑；出错时对「能带命令/文件内容」的工具**fail-closed**（挡住）。

```ts
/**
 * omp pre-tool guard — starter, 5 gates.
 *
 * Target:  ~/.omp/agent/hooks/pre/guards.ts
 * Runtime: omp imports this file itself (Bun, in-process). No separate bun install,
 *          no build step, no config entry — `hooks/pre/*.ts` is auto-discovered.
 * Reload:  restart omp. Editing the file in place does not re-import it (on Windows
 *          the loader's `?mtime` cache-buster is ignored by Bun).
 * Disable: move the file out of hooks/pre/ — there is no config switch.
 *
 * Gates (all deny-only; nothing here mutates a call):
 *   1 ai-attribution      AI trailers in a commit-shaped command or a commit-message file
 *   2 recursive-delete    recursive delete aimed at /, ~, $HOME, a drive root, or *
 *   3 nested-bash         bare `bash -c` / `bash -lc` (PATH resolves to the WSL shim)
 *   4 powershell-dollar   `powershell -Command "...$..."` (bash eats the $ first)
 *   5 unexpanded-temp-var a literal %TEMP% / %TMP% / %TMPDIR% in a path or command
 *
 * Deliberately NOT here: protected-process (killing chrome/codex/omp), board-write,
 * and the full "no recursive delete outside temp" rule. Those encode one machine's
 * policy; see adapters/omp.md §升级.
 *
 * Fail-closed: if the guard throws while evaluating a tool that can carry a command
 * or file content, that call is blocked. Read-only tools always pass.
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const COMMAND_TOOLS: Record<string, true> = { bash: true, python: true, notebook: true, computer: true };
const CONTENT_TOOLS: Record<string, true> = { write: true, edit: true };
const EFFECTFUL_TOOLS: Record<string, true> = { ...COMMAND_TOOLS, ...CONTENT_TOOLS, task: true, browser: true };

export interface Hit {
  rule: string;
  reason: string;
  hit: string;
}

function textOf(input: Record<string, unknown>): string {
  const parts: string[] = [];
  let budget = 200_000;
  const walk = (v: unknown, depth: number): void => {
    if (budget <= 0 || depth > 4) return;
    if (typeof v === "string") {
      const slice = v.slice(0, budget);
      budget -= slice.length;
      parts.push(slice);
      return;
    }
    if (Array.isArray(v)) {
      for (const item of v) walk(item, depth + 1);
      return;
    }
    if (v !== null && typeof v === "object") {
      for (const item of Object.values(v)) walk(item, depth + 1);
    }
  };
  walk(input, 0);
  return parts.join("\n");
}

function firstString(input: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = input[key];
    if (typeof value === "string") return value;
  }
  return "";
}



// --- gate 1: AI attribution in commit context --------------------------------

const ATTRIBUTION: RegExp[] = [
  /(?:^|[^a-z0-9_-])co-authored-by:[^\n]{0,120}(?:claude|codex|gpt|copilot|grok|gemini|anthropic|openai)/i,
  /noreply@anthropic\.com/i,
  /generated with\s*\[?\s*(?:claude|codex|copilot|grok)\b/i,
  /claude\.com\/claude-code/i,
];
const COMMIT_SHAPED = /\bgit\s+(?:commit|tag|merge|notes)\b|\bgh\s+(?:pr|issue)\s+(?:create|comment|edit)\b/i;
const COMMIT_MESSAGE_FILE = /(?:^|[\\/])\.git[\\/]|commit(?:-)?(?:msg|editmsg|message)\.txt$/i;

function attributionHit(text: string): string | null {
  for (const re of ATTRIBUTION) {
    const m = re.exec(text);
    if (m) return m[0].trim().slice(0, 120);
  }
  return null;
}

// --- gate 2: recursive delete of a root / home / drive ----------------------

const RM_RECURSIVE = /(?:^|[;&|(\n]\s*|\b)rm\s+((?:-{1,2}[A-Za-z-]+\s+)*)-[A-Za-z]*[rR][A-Za-z]*\b/i;
const PS_RECURSIVE = /\b(?:Remove-Item|rd|rmdir|del)\b[^\n;|&]*(?:-Recurse\b|\/s\b)/i;
const CATASTROPHIC_TARGET =
  /^(?:\/|~|\$HOME|\$\{HOME\}|%USERPROFILE%|\*|\/\*|\.|\.\.|[A-Za-z]:[\\/]?|[A-Za-z]:[\\/]\*)$/;

function deleteTargets(command: string): string[] {
  const targets: string[] = [];
  const add = (raw: string): void => {
    const token = raw.replace(/^['"`]+|['"`]+$/g, "");
    if (token.length > 0 && !token.startsWith("-")) targets.push(token);
  };
  const rm = RM_RECURSIVE.exec(command);
  if (rm) {
    const rest = command.slice(rm.index + rm[0].length);
    for (const token of rest.split(/[\s;|&]+/)) {
      if (token.length === 0) continue;
      if (token.startsWith("-")) continue;
      add(token);
    }
  }
  if (PS_RECURSIVE.test(command)) {
    for (const token of command.split(/[\s;|&]+/)) {
      if (/^[A-Za-z]:[\\/].*/.test(token) || token.startsWith("/") || token.startsWith("~") || token.startsWith("*")) add(token);
    }
  }
  return targets;
}

// --- gate 3: bare `bash -c` reaches the WSL shim, not Git Bash -------------

const BASH_EXEC_FLAG = /^-[A-Za-z]*c$/;
const PREFIXES: Record<string, true> = {
  sudo: true, env: true, time: true, nohup: true, xargs: true, command: true, exec: true, eval: true,
};

function nestedBashHit(command: string): string | null {
  for (const segment of command.split(/[;\n]|&&|\|\||\|/)) {
    const tokens = segment.split(/\s+/).filter(Boolean);
    for (let i = 0; i < tokens.length; i++) {
      const unquoted = tokens[i].replace(/^['"]+/, "");
      const word = unquoted.replace(/^[(`$'"{}]+/, "").replace(/[)`}'"]+$/, "").toLowerCase();
      if (word !== "bash" && word !== "bash.exe") continue;
      // Inside `$(...)` or backticks the shell always executes the word, so there is
      // no prose reading to protect: `echo "$(bash -c id)"` is a real call.
      const substituted = /^[(`$]/.test(unquoted);
      const previous = i > 0 ? tokens[i - 1].replace(/^[(`$'"{}]+/, "").toLowerCase() : "";
      const atStart = i === 0 || substituted || PREFIXES[previous] === true || /^[A-Za-z_][A-Za-z0-9_]*=/.test(previous);
      if (!atStart) continue;
      for (let j = i + 1; j < tokens.length; j++) {
        const next = tokens[j].replace(/^['"]+|['"]+$/g, "");
        if (!next.startsWith("-")) break;
        if (BASH_EXEC_FLAG.test(next)) return segment.trim().slice(0, 200);
      }
    }
  }
  return null;
}

// --- gate 4: bash expands $ before PowerShell sees it -----------------------

const PS_COMMAND = /\b(?:powershell|pwsh)(?:\.exe)?\b[\s\S]{0,240}?\s-(?:Command|c)\s+/gi;

function bareDollarAfter(rest: string): boolean {
  let quote: "'" | '"' | null = null;
  for (let i = 0; i < rest.length; i++) {
    const c = rest[i];
    if (quote === "'") {
      if (c === "'") quote = null;
      continue;
    }
    if (quote === '"') {
      if (c === '"' && rest[i - 1] !== "\\") quote = null;
      else if (c === "$" && rest[i - 1] !== "\\") return true;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      continue;
    }
    if (c === "\n" || c === ";" || c === "|") return false;
    if (c === "&" && rest[i + 1] === "&") return false;
    if (c === "$" && rest[i - 1] !== "\\") return true;
  }
  return false;
}

function powershellDollarHit(command: string): string | null {
  PS_COMMAND.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = PS_COMMAND.exec(command)) !== null) {
    const rest = command.slice(m.index + m[0].length);
    if (bareDollarAfter(rest)) return command.slice(m.index, m.index + 160);
  }
  return null;
}

// --- gate 5: literal %TEMP% is not a path this shell expands ----------------

const UNEXPANDED_TEMP = /(?:^|[\s"'=:/\\])%(?:TEMP|TMP|TMPDIR)%/i;

// --- verdict ----------------------------------------------------------------

export function guardHit(tool: string, input: Record<string, unknown>): Hit | null {
  const command = firstString(input, ["command", "cmd", "script", "code"]);
  const path = firstString(input, ["path", "file_path", "filePath", "target"]);

  if (COMMAND_TOOLS[tool] === true && command.length > 0) {
    if (COMMIT_SHAPED.test(command)) {
      const trailer = attributionHit(command);
      if (trailer) {
        return {
          rule: "ai-attribution",
          reason: "Commit messages must not carry an AI-attribution trailer. Drop the trailer; the commit stands on its own.",
          hit: trailer,
        };
      }
    }
    const target = deleteTargets(command).find(t => CATASTROPHIC_TARGET.test(t));
    if (target) {
      return {
        rule: "recursive-delete",
        reason: `Recursive delete of '${target}' is refused. Name the exact subtree you mean, and take a backup path + sha256 first.`,
        hit: target,
      };
    }
    const nested = nestedBashHit(command);
    if (nested) {
      return {
        rule: "nested-bash",
        reason: "A bare `bash -c` resolves to the WSL shim on Windows and dies on an unmounted disk. Call the shell you mean by full path, or drop the nesting.",
        hit: nested,
      };
    }
    const ps = powershellDollarHit(command);
    if (ps) {
      return {
        rule: "powershell-dollar",
        reason: "bash expands `$` before PowerShell sees it. Wrap the PowerShell body in single quotes, or escape as \\$.",
        hit: ps,
      };
    }
    if (UNEXPANDED_TEMP.test(command)) {
      return {
        rule: "unexpanded-temp-var",
        reason: "A literal %TEMP% is not expanded by this shell; it names a relative path and would create a directory called '%TEMP%' in the cwd. Use $TEMP (bash) or $env:TEMP (PowerShell).",
        hit: "%TEMP%",
      };
    }
  }

  if (CONTENT_TOOLS[tool] === true) {
    if (COMMIT_MESSAGE_FILE.test(path)) {
      const trailer = attributionHit(textOf(input));
      if (trailer) {
        return {
          rule: "ai-attribution",
          reason: "This file is a commit message; it must not carry an AI-attribution trailer.",
          hit: trailer,
        };
      }
    }
    if (UNEXPANDED_TEMP.test(path)) {
      return {
        rule: "unexpanded-temp-var",
        reason: "The target path contains a literal %TEMP%; it is not expanded and would land in the cwd.",
        hit: path.slice(0, 160),
      };
    }
  }

  return null;
}

// --- audit log --------------------------------------------------------------

const BUCKET_MS = 3_600_000;
const HOME = process.env.USERPROFILE ?? process.env.HOME ?? ".";
const LOG_DIR = join(HOME, ".omp", "agent", "hooks", "log");

function logBlock(record: Record<string, unknown>): void {
  try {
    mkdirSync(LOG_DIR, { recursive: true });
    appendFileSync(join(LOG_DIR, `guard.${Math.floor(Date.now() / BUCKET_MS)}.log`), `${JSON.stringify(record)}\n`, "utf8");
  } catch {
    // an audit-log failure must never change a verdict
  }
}

// --- factory ----------------------------------------------------------------

export default function guards(pi: ExtensionAPI): void {
  pi.on("tool_call", (event, ctx) => {
    const tool = String(event.toolName);
    const raw = event.input;
    const input: Record<string, unknown> = raw !== null && typeof raw === "object" ? { ...(raw as Record<string, unknown>) } : {};
    try {
      const hit = guardHit(tool, input);
      if (hit === null) return;
      logBlock({ ts: new Date().toISOString(), decision: "block", rule: hit.rule, tool, cwd: ctx.cwd, hit: hit.hit });
      return { block: true, reason: `[${hit.rule}] ${hit.reason}` };
    } catch (error) {
      if (EFFECTFUL_TOOLS[tool] !== true) return;
      logBlock({ ts: new Date().toISOString(), decision: "block", rule: "guard-error", tool, error: String(error) });
      return { block: true, reason: "Guard failed while evaluating this call; failing closed." };
    }
  });
}
```

### 4.3 装 + 重启

```bash
mkdir -p ~/.omp/agent/hooks/pre
# 把 §4.2 的内容写到 ~/.omp/agent/hooks/pre/guards.ts
```

然后**重启 omp**（关掉进程重开）。会话内改文件不生效。

### 4.4 验收

**V4 加载成功（免费，决定性）：**

```bash
printf '%s\n' '{"id":"1","type":"get_state"}' \
  | omp --mode rpc --no-session --cwd "$PWD" >/dev/null 2>hook-err.txt
grep -c "Failed to load extension" hook-err.txt || true
# 期望 0。非 0 就把那一行原样贴出来 —— 那是 TS 语法/import 错误，不是路径错。
```

**V5 真的拦得住（要一次真实工具调用）：**

在任意会话里让 agent 跑：

```
bash -c "echo hi"
```

期望：**被拒绝**，理由里带 `[nested-bash]`。然后看日志：

```bash
ls -t ~/.omp/agent/hooks/log/guard.*.log | head -1
grep -c '"decision":"block"' "$(ls -t ~/.omp/agent/hooks/log/guard.*.log | head -1)"
# 期望 ≥1
```

**行为判据（逐条让 agent 跑，对照期望）：**

| 让它跑 | 期望 |
|---|---|
| `bash -c "echo hi"` | 拦（`nested-bash`） |
| `powershell -Command "$x = 1"` | 拦（`powershell-dollar`） |
| `powershell -Command '$x = 1'` | 放（单引号是正解） |
| `git commit -m "x\n\nCo-Authored-By: Claude <noreply@anthropic.com>"` | 拦（`ai-attribution`）；**用 `--dry-run` 或临时仓库测** |
| `echo x > %TEMP%/a.txt` | 拦（`unexpanded-temp-var`）；真跑过去会在 cwd 建一个叫 `%TEMP%` 的目录，事后删掉 |

> **递归删除那道门不要在生产环境试**：`rm -rf /` 一旦没拦住就是灾难。它只由纯函数判据覆盖（目标 ∈ `/`、`~`、`$HOME`、`C:/`、`*`、`.`、`..`），要测就在一次性容器/虚拟机里测。

### 4.5 从 5 道门升到 7 道门

7 道门在 omp 上都能重建（形状见 [`README.md`](README.md)）；但其中 3 道绑的是**策略偏好**，不适合默认发给别人。本文只发 5 道，差的 3 道和它们的性质：

| 缺的门 | 拦什么 | 为什么不能自动装 |
|---|---|---|
| `protected-process` | 杀 chrome / codex / omp | 用户可能**就是想**杀浏览器；这是偏好，不是通例 |
| `board-write` | 看板文件只许追加 | 绑死某个 `board.py` 和它的目录布局 |
| `recursive-delete`（全量版） | 临时目录外**任何**递归强删 + 按行放行清单 | 会挡住正常的 `rm -rf ./build`；需要配套的 `hooks/allow/*.txt` 机制 |

加法：在 `guardHit()` 里加一个分支，返回 `{ rule, reason, hit }`；`GUARDS` 是线性表，顺序即优先级。加完**必须重启**再验。

---

## 5 · 不能自动做的

1. **不能替你选 profile / 目录**。`--profile`、`PI_CODING_AGENT_DIR` 都会换掉整个 agent 目录；装错地方等于没装。
2. **不能覆盖已有的 `RULES.md` / `AGENTS.md`**。先备份，再合并；整份盖掉别人的规则是事故。
3. **hooks 必须先给用户看全文再装**。它在 `tool_call` 上 fail-closed：写错会挡住正常干活。
4. **不能把 7 道门原样搬**。三道绑死一台机器（§4.5），搬过去会误伤。
5. **不能自动验证「模型会遵守」**。`get_state` 只能证明规则**进了提示词**（免费、决定性）；遵守与否要一次真实调用 + 观察输出。
6. **不能自动重启 omp**。hooks 只在进程启动时 import。
7. **不能替你开 `tools.approvalMode: yolo`**。YOLO 不是授权；hooks 说停就得停。
8. **不能把 `RULES.md` 放项目级而不问**。项目级会遮蔽更远的 `.omp/RULES.md`，而且只在「最近的非空 `.omp/`」里找——放错层级会静默失效。
9. **不能用 `omp read rule://RULES` 验收**。会话外它返回 `Unknown rule`，那是正常现象。
10. **不需要装 bun**（实测 §1.4c）。只有你想自己跑 `tsc` 类型检查时，才需要 node/bun + `@oh-my-pi/pi-coding-agent` 的类型包——**没网就跳过**，omp 自己 import 时不做类型检查。

---

## 6 · 回滚

```bash
# 档 B：先摘 hook（不用改配置，没有开关）
mv ~/.omp/agent/hooks/pre/guards.ts ~/.omp/agent/hooks/pre/guards.ts.disabled-$(date +%Y%m%d)
# 档 A：恢复备份
mv ~/.omp/agent/RULES.md.before-agentrule-<date>  ~/.omp/agent/RULES.md
mv ~/.omp/agent/AGENTS.md.before-agentrule-<date> ~/.omp/agent/AGENTS.md
```

回滚后重跑 V2（期望 0）和 V4（期望 0）确认真的撤掉了。

---

## 7 · 踩过的坑

1. **以为 `RULES.md` 可以很长**。它每请求全文注入：6.7 KB = 2,174 tokens（o200k），每个请求都付。案例、模板、方法都放 `library/`。
2. **把子代理要守的规矩写进 `AGENTS.md`**。子代理按文件名过滤掉 `AGENTS.md`，只继承 `RULES.md`（§1.4b 实测）。
3. **改完 hook 不重启**。Windows 上原地改 `.ts` 不会被重新 import；症状是「我改了但它还是老行为」。
4. **以为要装 bun**。omp 是自带运行时的单文件可执行程序，`.ts` factory 由它自己 import（§1.4c 的 PATH 实验）。
5. **以为 `omp read skill://x` 能验项目级 skill**。外部命令路径只认用户级；项目级要在会话里看 `skill:x` 命令在不在。
6. **把 `.omp/` 建成空目录**。空目录在向上查找时被跳过；`RULES.md` 只有在**非空**的最近 `.omp/` 里才被认。

---

## 8 · 证据（原样输出）

| 断言 | 命令 | 实测输出 |
|---|---|---|
| 版本 | `omp --version` | `omp/18.14.1` |
| 顶层条目 | `ls -1 ~/.omp/agent \| wc -l` | `94` |
| hook 数量 | `ls -1 hooks/pre/*.ts hooks/post/*.ts \| wc -l` | `7`（pre 2 + post 5） |
| skill 数量 | `ls -1 ~/.omp/agent/skills \| wc -l` | `17` |
| `RULES.md` 成本 | `omp toks RULES.md` | `2,174` tokens（o200k） |
| 规则进提示词 | `get_state` + `grep -c` | 带规则 `1` / `--no-rules` `0`；19,589 vs 15,756 字符 |
| 子代理只拿 RULES | 子代理 `session_init.systemPrompt` | 20,967 字符，含 `RULES.md`，不含 `AGENTS.md` |
| hook 无需 bun | 受限 `PATH` + 项目级 hook | `probe-xyz` 计数 `1` |
| hook 加载失败可见 | `--hook broken.ts` | stderr `Failed to load extension …` |
| 5 道门判据 | 25 条断言（命中 / 不命中 / factory 接线） | 25 pass / 0 fail |

最后一条的测试文件不随仓库发——判据就是 §4.4 那张行为表，任何人都能自己跑一遍。

<!-- source: ops/oss/03-ADAPTER-CODEX.md (lane AdapterCodex) · measured on codex-cli 0.165.0, Windows, 2026-11-02 -->
# Codex 适配

> EN: Where each rule file goes on Codex, and the one command that proves Codex reads it.

这一页只回答两件事：**在 Codex 上每个文件放哪**，以及**怎么证明 Codex 真的读了它**。规则本身写什么，看 [`protocol/00-floor.md`](../protocol/00-floor.md)；派发和验收的通用流程，看 [`protocol/02-dispatch.md`](../protocol/02-dispatch.md)。

Codex 的脾气和另外两套不一样：**规则文本**没有「加载整个目录」的机制，只有一条 `AGENTS.md` 链；配置全在一个 TOML 里；钩子要用户点一次「信任」才跑。所以适配的重点不是改配置，是**把文本放到对的目录**。

---

## 0. 先问，不要猜

四个问题，答不上来就停：

| # | 问什么 | 猜错的后果 |
|---|---|---|
| 1 | `CODEX_HOME` 在哪？（默认 `~/.codex`，可能被环境变量改掉） | 写错目录 = 全局规则永远不生效，而且没有任何报错 |
| 2 | 只装这台机器（全局），还是只装某个仓库？ | 全局会影响所有项目；装错层会让无关项目也吃这套规则 |
| 3 | `codex --version` 是多少？ | 低于 0.165.0 没有 `debug prompt-input`，本文的验证命令全部失效 |
| 4 | 用 ChatGPT 订阅登录，还是 API key？ | 决定额度怎么描述，以及能不能用 `codex login status` 判断 |

另外两条**不要替用户决定**：

- **要不要开 hooks**：hooks 需要用户在 Codex 里批准一次，批准前写了等于没写。用户不点头就不装。
- **仓库里已经有 `AGENTS.md` 吗**：有就改，不要覆盖。

**停的条件**（命中任一就停）：不知道 `CODEX_HOME` · 不知道装哪一层 · 已有 `AGENTS.md` 且与规则冲突 · 用户没回答登录方式 · 版本低于 0.165.0 且用户不接受降级验证。

**可以直接抄的问法：**

> 我要在你的 Codex 上装一套规则。需要你确认：① `codex --version` 输出什么？② 只装这台机器，还是只装某个仓库？③ 你用 ChatGPT 订阅还是 API key？④ 要不要装 hooks（能在工具调用前拦命令，但需要你点一次「信任」）？其余我自己查。

---

## 1. 文件放哪（一张表）

| 你要装的东西 | 放哪 | 生效方式 |
|---|---|---|
| 全局规则 | `$CODEX_HOME/AGENTS.md` | 每轮注入，所有项目都吃 |
| 项目规则 | `<repo>/AGENTS.md`（git root） | 每轮注入，只影响这棵目录树 |
| 子目录特例 | `<repo>/<sub>/AGENTS.md` | 追加在根规则后面，**冲突时更深的赢** |
| 覆盖某个目录 | `<repo>/<sub>/AGENTS.override.md` | **顶掉**同目录的 `AGENTS.md`（不是合并） |
| 技能 | `<repo>/.codex/skills/<name>/SKILL.md` | 只把 `name` + `description` 塞进索引，正文模型自己决定读不读 |
| 全局技能 | `$CODEX_HOME/skills/<name>/SKILL.md` | 同上 |
| 钩子 | `<repo>/.codex/hooks.json` | 事件触发；**需要用户批准一次** |
| MCP | `$CODEX_HOME/config.toml` 的 `[mcp_servers.*]` | 启动时拉起 |
| 项目级配置 | `<repo>/.codex/config.toml` | **只在受信任的仓库里生效**，且只认部分键 |

**绝对不要手改的**：`auth.json`（登录凭据）、`*.sqlite`（运行时数据库）、`sessions/`、`plugins/`。这些不是配置，改坏了只能重装。

Codex 目录的实测构成（0.165.0 样本）：顶层 **88 项 = 51 文件 + 33 目录**，递归 9,040 个文件里 **95% 是插件缓存**（`plugins/` + `.tmp/`）。真正属于「你该写的」只有四个：`config.toml`、`AGENTS.md`、项目里的 `.codex/hooks.json`、`skills/*/SKILL.md`。

---

## 2. 最小安装（十分钟，不改任何配置）

适用：让 agent 每轮看到规则就够，不需要强制拦截。

### 2.1 备份

```bash
cd "$CODEX_HOME" && cp AGENTS.md "AGENTS.md.before-<你的标记>-$(date +%Y%m%d)" 2>/dev/null || true
```

文件不存在就不用备份。用 `cp` 不要用 `mv` —— 备份必须与原文件同目录、随时能换回去。

### 2.2 写全局 `AGENTS.md`

只放三类内容，**200 行以内**：

1. 身份与语言（对谁说话、代码和 commit 用什么语言）
2. 回复形状（第一行给什么、最多几条、结论带不带 `path:line`）
3. 入口指针（详细规则在哪、什么时候去读）

内容取自 [`protocol/00-floor.md`](../protocol/00-floor.md)，**不要**把整本规则书粘进来 —— 常驻文本越长，模型对每一条的注意力越薄。

形状（把尖括号处换成实际条目）：

```markdown
# 全局

<常驻条目：从 protocol/00-floor.md 取，5–10 条，只留「不看就会犯」的>

详细规则在 <repo>/protocol/，用到哪篇读哪篇；不要整目录预载。
```

写完确认大小：

```bash
wc -lc "$CODEX_HOME/AGENTS.md"
```

### 2.3 写项目 `AGENTS.md`

放 git root，只写**这个仓库特有**的东西：怎么跑测试、目录约定、哪些目录只读、派发时 brief 怎么写。通用规则已经在全局那份里，不要复制。

### 2.4 验证（这一步不能省）

```bash
cd <repo> && codex debug prompt-input "verify" | grep -c "<你写进 AGENTS.md 的一句独特的话>"
```

PowerShell：

```powershell
codex debug prompt-input "verify" | Select-String -SimpleMatch "<你写进 AGENTS.md 的一句独特的话>"
```

**判据**：计数 ≥ 1。是 0 就回第 1 节对位置；想确认这句话落在 `<INSTRUCTIONS>` 块里而不是别处，用第 5 节的完整检查。

### 2.5 回滚

```bash
rm "$CODEX_HOME/AGENTS.md" && mv "$CODEX_HOME/AGENTS.md.before-<你的标记>-<date>" "$CODEX_HOME/AGENTS.md"
```

项目那份是新增文件，直接删。

---

## 3. 完整安装（每项独立，按需上）

最小安装已经够用。下面每一项都要用户**真的需要强制**才装，不要一次全上。

### 3.1 `config.toml`：最多加三个键

```toml
# 规则书超过 32 KiB 才需要（默认 32768，超了静默截断，见 §4.5）
project_doc_max_bytes = 65536

# 让 Codex 在没有 AGENTS.md 的目录里也能读 Claude Code 的 CLAUDE.md
project_doc_fallback_filenames = ["CLAUDE.md"]

[skills]
max_context_tokens = 10000
```

改完用 `codex doctor --summary` 的 `config loaded` 一行确认没写坏。

### 3.2 项目级 `.codex/config.toml`：只在受信任仓库生效

- 未受信任的仓库里放这个文件，Codex **完全不读**，连警告都没有。
- 要让它生效，必须把仓库写进**当前 `CODEX_HOME` 的** `config.toml`：

  ```toml
  [projects.'c:\path\to\repo']   # 路径按 Codex 自己记录的形式写（实测为小写、单引号）
  trust_level = "trusted"
  ```

  用命令行 `-c` 覆盖信任**不生效** —— 信任判定只认落盘的配置。
- 受信任后实测生效的键：`instructions`、`model`、`sandbox_mode`。不支持的键会被忽略并提示（二进制里有 `Ignored unsupported project-local config keys`）。

**结论**：项目配置不是主配置。跨项目一致的放 `$CODEX_HOME/config.toml`，项目偏好放项目 `AGENTS.md`。

### 3.3 hooks：能拦命令，但要用户批准

Codex 的 hooks 默认开启：`codex features list` 里能看到 `hooks  stable  true`（本文实测 0.165.0）。文件在项目里：`<repo>/.codex/hooks.json`。更老的版本先用 `codex features list | grep '^hooks'` 自查，看不到这一行就是没有这个 feature，按本节末尾处理。

```json
{
  "description": "为什么需要这个钩子",
  "hooks": {
    "PreCompact": [
      {
        "matcher": "^(manual|auto)$",
        "hooks": [
          { "type": "command", "command": "python -X utf8 \"<abs path>/hook.py\"", "timeout": 10 }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "^(startup|resume|clear|compact)$",
        "hooks": [
          { "type": "command", "command": "python -X utf8 \"<abs path>/hook.py\"",
            "additionalContextLimit": 700, "timeout": 10 }
        ]
      }
    ]
  }
}
```

14 个事件（PascalCase）：`PreModelRequest` `PostModelRequest` `PreToolUse` `PermissionRequest` `PostToolUse` `PreCompact` `PostCompact` `SessionStart` `SessionEnd` `UserPromptSubmit` `SubagentStart` `SubagentStop` `Stop` `Interrupt`。

**第一次不生效是正常的。** 用户批准后 Codex 才写进 `config.toml`：

```toml
[hooks.state.'<abs path to hooks.json>:<event_snake>:0:0']
enabled = true
trusted_hash = "sha256:…"
```

自动化场景可以用 `codex --dangerously-bypass-hook-trust` 跳过信任 —— 只在你已经审过钩子来源时用。

**「文件在」和「钩子受信任」是两回事，只有后者决定门是真的：**

```bash
# 第一条：文件在（这不能证明任何事）
ls -l <repo>/.codex/hooks.json

# 第二条：受信任（必须在当前 CODEX_HOME 的 config.toml 里看到对应条目）
grep -n "hooks.state" "$CODEX_HOME/config.toml"
```

第二条要能看到一条键，里面同时含 `hooks.json` 的绝对路径和你要的事件名（例如 `pre_tool_use`）。**只过第一条 = 门是装饰**：文件躺在那里，一次都不会跑。

**验证钩子真跑了**：让钩子自己往日志追加一行，开一次会话后看日志有没有新行。文件在 + 有信任条目 + 日志有新行，三条齐了才叫「装好了」。

**旧版 Codex（没有 `hooks` feature）**：[`protocol/03-gates.md`](../protocol/03-gates.md) 里的每一道门都退化成**书面规则**。这不是「没有门」，是「门交给模型自己遵守」—— 写文档时必须说清这个区别，否则读者会以为规则有强制力。

### 3.4 技能：项目级比全局好用

```bash
mkdir -p <repo>/.codex/skills/my-skill
```

```markdown
---
name: my-skill
description: 一句话说清「什么时候该用我」——这是模型唯一能看到的判断依据
---

正文写步骤；可以引 references/ 下的文件。
```

`description` 写不好 = 技能永远不会被调用。想复用别的 harness 的技能，直接建符号链接也行 —— 实测链接目标会出现在技能索引里（`(file: r0/<name>/SKILL.md)`），Codex 不要求技能是真实目录。

### 3.5 MCP：能不加就不加

```bash
codex mcp add <name> -- <command> [args...]   # stdio
codex mcp add <name> --url <url>              # HTTP
codex mcp list
```

代价是启动握手时间和上下文里的工具描述。`codex doctor` 因为「缺 MCP 环境变量」报 warn 是配置有可选问题，不是坏。

### 3.6 什么时候**不要**上完整安装

只有一个仓库一个人用 · 团队 Codex 版本不齐 · 用户不愿点「信任」 · 规则还在天天改。这四种情况，最小安装就够了。

---

## 4. 已知限制

### 4.1 额度是 ChatGPT 订阅的周额度

```bash
codex login status
# Logged in using ChatGPT
```

这种模式吃的是 **ChatGPT 订阅的周额度**，不是按 token 计费的 API 额度。长会话、多子代理、大仓库扫描会把它打满，打满要等周期重置。

- 判断模式只有一条可靠命令：`codex login status`。
- **额度不是本地可查的健康指标**：`codex doctor` 不报额度项。
- 对外要说清楚：**这套规则不降低额度消耗，只让每次调用更值**。把 `AGENTS.md` 控制在几百行、不预载整本规则书，本身就是省额度。

### 4.2 `thread_history_1.sqlite` 完整性检查失败（已知问题）

`codex doctor` 会报：

```
[XX] state   …\thread_history_1.sqlite database failed integrity check
19 ok | 9 notes | 5 warn | 1 fail
```

独立复核（只读 `PRAGMA quick_check`）返回：

```
*** in database main ***
Tree 5 page 5 right child: Failed to read ptrmap key=28203
Tree 5 page 28203: btreeInitPage() returns error code 11
…
```

- **是什么**：会话历史索引的 B 树页坏了。`quick_check` 在第一个坏点就返回，所以这不是全库扫描结论 —— 只证明「至少这些页坏了」。
- **影响**：历史检索、按 id 恢复旧会话、`doctor` 的 threads 检查（常伴 `rollout files are missing from the state DB`）。**不影响**读代码、跑命令、写文件、加载 `AGENTS.md`。
- **不要删这个文件**。它旁边有 `-wal` / `-shm`，删了等于丢光历史，而且 Codex 会重建一个空库，看起来「修好了」其实是数据没了。
- **处置顺序**：① 整目录备份 `thread_history_1.sqlite*` ② `codex doctor`（不带 `--summary`）看详情 ③ 需要迁移旧会话用 `codex migrate-rollouts` ④ 修不好就接受，只影响历史功能。
- 文档里写成「已知问题 + 影响范围」，不要写成「待修 bug」—— 它不是部署能解决的。

### 4.3 hooks 是「信任门控」的

新放一个 `hooks.json`，在没有 `[hooks.state]` 条目之前**完全不执行**，也没有任何报错。这是最容易误判成「Codex 不支持 hooks」的地方。

### 4.4 项目配置只在受信任仓库生效

见 §3.2：未受信任 = 静默不读；受信任 = 仍会忽略不支持的键。

### 4.5 `AGENTS.md` 超限静默截断

默认 **32,768 字节**。超了没有任何提示，模型只看到前半截。实测：40,000 字节的文件只进去 32,768 字节，尾部内容直接消失。

**这是「文件存在 ≠ 模型看到」最常见的原因**，也是为什么 §2.4 的验证不能省。

### 4.6 只加载 git root → cwd 这一条链

- 非 git 目录：**只**加载 cwd 那一层，不向上走。
- 兄弟目录、`../other` 的 `AGENTS.md` 不会自动加载，需要时得让 agent 显式去读。
- `AGENTS.override.md` 会**顶掉**同目录的 `AGENTS.md`，不是合并。

### 4.7 技能是索引，不是强制

`SKILL.md` 只把 `name` + `description` 放进上下文，正文模型自己决定读不读。指望技能「自动执行」是误解。

### 4.8 Windows 特有

- 默认 shell 是 `powershell`。双引号里的 `$` 会被展开，写命令用单引号或反引号转义。
- 沙箱可以开到 `danger-full-access` + `approval_policy = "never"`，那是最松的组合，只适合单机自用。
- `codex doctor` 会警告 Microsoft Defender 可能干扰 Codex。

### 4.9 版本漂移

`debug prompt-input`、hooks 事件名、项目配置白名单都可能在版本间变。部署前跑 `codex --version`，并在文档里写清「实测于哪个版本」。

---

## 5. 验证

### 5.1 标准验证（不消耗额度，不需要网络）

```bash
cd <repo> && codex debug prompt-input "verify" \
  | grep -o -e "AGENTS.md instructions" -e "project-doc" -e "<全局那句>" -e "<项目那句>" \
  | sort | uniq -c
```

判据：

1. `AGENTS.md instructions` 出现 —— 注入发生了；
2. 你写的那句独特的话，各出现 **1 次** —— 内容没被截断、没被 `AGENTS.override.md` 顶掉；
3. `--- project-doc ---` **只在同时装了全局和项目两份时才出现一次**。只装一份时它根本不出现 —— **别把它当失败**。

第 3 条是实测出来的坑：分隔符和 `for <cwd>` 后缀都是「有项目文档」才加的。全局单独装时标题只有 `# AGENTS.md instructions`（没有 `for`），项目单独装时没有分隔符。**只有两份都在，才两者齐全。**

PowerShell 用 `Select-String -SimpleMatch` 逐条查，判据相同。

`debug prompt-input` 是本地渲染：实测在**空的 `CODEX_HOME`、没有 `auth.json`** 的情况下也能返回 0。

### 5.2 降级验证（Codex < 0.165.0）

按顺序，每条都比上一条贵：

1. `codex --help` 看有没有别的 dump 子命令。
2. 开一次 TUI，让它复述 `AGENTS.md` 第一行 —— **会消耗额度**，但只有一句话。
3. 最后才用 `codex exec "…"` 跑完整一轮。

### 5.3 部署后体检

```bash
codex doctor --summary --no-color --ascii
```

装之前先记一次基线（本机 0.165.0 是 `19 ok | 9 notes | 5 warn | 1 fail`）。装完之后，多出来的 warn 就是你改坏了什么。

---

## 6. 卸载

| 装了什么 | 怎么撤 |
|---|---|
| 全局 `AGENTS.md` | 删除，或把 `.before-*` 备份换回去 |
| 项目 `AGENTS.md` | 删新增文件；追加过的用备份 diff 回去 |
| `config.toml` 三个键 | 删那三行，`codex doctor --summary` 确认 `config loaded` |
| `[projects.'…'] trust_level` | 删掉该段，项目配置自动失效 |
| `.codex/hooks.json` | 删文件 **+** 删 `config.toml` 里对应的 `[hooks.state.'…']`（只删文件会留悬空信任条目） |
| 项目技能 | 删 `<repo>/.codex/skills/<name>/` |
| MCP | `codex mcp remove <name>` |
| 登录 | `codex logout`（所有会话都会退出，谨慎） |

---

## 7. 这一页不保证什么

1. **没有端到端验证「模型按规则干活」。** 只验证了「规则进了 prompt」。真跑一轮 `codex exec` 要花订阅额度，部署阶段不要花。
2. 只在 **0.165.0 / Windows** 实测。macOS / Linux 的路径分隔符和默认 shell 不同，`hooks.json` 的 `command` 要跟着改。
3. 项目配置只实测了 `instructions` / `model` / `sandbox_mode` 三个键。
4. 没验证 API key 模式下的额度表现。
5. `thread_history_1.sqlite` 的损坏范围只由 `quick_check` 的**首次失败**确定，不是全库结论。

---

## 8. 和另外两套比，Codex 只在这三点上不同

适配层只关心差异；逐项对照在 [`adapters/README.md`](README.md)。

1. **规则只有 `AGENTS.md` 一条链，没有目录扫描。** 只走 git root → cwd，且 `AGENTS.override.md` 是**顶掉**不是合并。放错目录 = 静默不加载，没有任何报错。
2. **配置只有一个 `config.toml`，项目级还要先受信任。** 项目 `.codex/config.toml` 在未受信任的仓库里完全不读，命令行 `-c` 也绕不过去 —— 信任只认落盘的 `[projects.'…']`。
3. **钩子要用户批准一次才跑。** `hooks.json` 写好只是第一步；`config.toml` 里出现 `[hooks.state]` 条目才算装好。旧版 Codex 没有这个 feature，门退化成书面规则。

规则内容、派发流程、验收标准三套一样，都在 [`protocol/`](../protocol/README.md)，不要在这里重复。

# 卸载与回退

> EN: How to remove the rules, gates and entry blocks and prove nothing is left.

**一句话**：卸载是「按清单删」，回退是「按备份还原」，关门是「只停 hook」——三件事三套动作，混着做一定出事。

本文假设你已经装过（见 `INSTALL.md`）。没装过就不用读。所有命令都可以先只读跑一遍再执行。

---

## 0 · 先分清三件事

| 你要什么 | 叫什么 | 依据 | 结果 |
|---|---|---|---|
| 以后不想用这套规则了 | **卸载** | `manifest.json` / 安装报告里的文件清单 | 文件消失，入口干净 |
| 刚装完就出问题，想回到装之前 | **回退** | 安装前的备份 + `before_sha256` | 逐字节等于安装前 |
| 只想让门别拦我，规则还留着 | **关门** | 各 harness 自己的开关 | 规则还在，hook 不跑 |

三条硬规矩，对三种动作都成立：

1. **先备份再动手。** 卸载也是删除，删除也要可逆：把要删的东西 `Move-Item` 到一个带时间戳的目录，确认没问题再清。
2. **hash 对不上就停。** 安装后被用户改过的文件（当前 hash ≠ `after_sha256`），不许直接删或还原；先给 diff，让用户选「保留我的修改 / 强制还原 / 只删托管块」。
3. **别删整个配置目录。** `~/.omp/agent`、`~/.codex`、`~/.claude` 里有用户自己的模型、权限、历史和插件；只动清单里的路径。

---

## 1 · 动手前先拿到两样证据

### 1.1 安装报告 / manifest

安装流程把「装了什么」留在两处：

- 运行目录 `<state-dir>/manifest.json`（默认 `~/.agentrule-deploy/<run-id>/`，见 `../protocol/04-recovery.md`）
- 安装器结尾打印的 `[done]` 段落（写入数、备份目录）

manifest 里卸载要用的字段：

| 字段 | 用途 |
|---|---|
| `plan.steps[].path` | 这次碰过的绝对路径 |
| `plan.steps[].before_sha256` | 安装前的内容指纹；回退成功与否的判据 |
| `plan.steps[].backup` | 备份文件位置 |
| `applied[].after_sha256` | 安装后的指纹；用来判断「装完之后用户改没改」 |

### 1.2 备份目录

- **脚本安装**：`<target>/.backup-YYYYMMDD-HHMMSS/`，里面是**被覆盖**的文件，保持相对路径（`<target>` 默认就是家目录）。
- **手工安装**：同目录的 `*.before-bootstrap-YYYYMMDD`（见 `../protocol/04-recovery.md`）。

只新建、没覆盖任何东西的安装，**不会有备份目录**——这不是失败，说明没有旧内容需要还原。

### 1.3 两样都没有怎么办

不要凭印象删。用「和仓库副本逐字节比对」重建清单：

```powershell
# PowerShell：列出 AgentRule/ 下每个文件是否与仓库副本一致
$repo = "C:\path\to\AgentRule-repo"          # ← 改成你解压/克隆的位置
$inst = Join-Path $HOME ".omp\agent\AgentRule"
Get-ChildItem -LiteralPath $inst -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  $rel  = $_.FullName.Substring($inst.Length + 1)
  $src  = Join-Path $repo $rel
  $same = (Test-Path -LiteralPath $src) -and
          ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq
           (Get-FileHash -LiteralPath $src      -Algorithm SHA256).Hash)
  "{0}  {1}" -f $(if ($same) { "SAME  " } else { "DRIFT " }), $rel
}
```

```bash
# bash：同上
repo="/path/to/AgentRule-repo"; inst="$HOME/.omp/agent/AgentRule"
find "$inst" -type f 2>/dev/null | while IFS= read -r f; do
  rel="${f#$inst/}"; src="$repo/$rel"
  if [ -f "$src" ] && cmp -s "$f" "$src"; then printf 'SAME   %s\n' "$rel"
  else printf 'DRIFT  %s\n' "$rel"; fi
done
```

判读：`SAME` 的可以删；`DRIFT` 的停下来问用户。**一个都列不出来**，说明这个目录根本不是这套东西装的——别删。

---

## 2 · 通用顺序（三套 harness 都一样）

1. **退出 harness。** 三套都在启动时读配置和 hook；运行中改文件，当前会话不会变，还可能因为文件被占用写失败。
2. **算当前 hash 并落盘**（卸载前证据）：`Get-FileHash` / `sha256sum` 输出存一份。
3. **先关门，再删文件。** 顺序反了会有一小段时间「规则没了、门还在」，误拦的命令没有解释。
4. **删规则目录**（整目录移走，不递归强删）。
5. **处理入口文件**：删托管块；如果入口文件是安装器新建的，整个文件删掉。
6. **验证**（§3.5 / §4.5 / §5.5 的检查命令全 `PASS`）。
7. **最后才清备份和暂存目录。** 确认无误之前，暂存目录就是你的后悔药。

三个**停手条件**（命中任一就停，别硬做）：

- 有 `DRIFT` 文件；
- 备份目录存在但 `before_sha256` 对不上；
- harness 起不来，或启动时报配置错误。

---

## 3 · omp

### 3.1 落点

| 路径 | 谁写的 | 卸载动作 |
|---|---|---|
| `~/.omp/agent/AgentRule/` | 安装器（整个目录都是这套规则） | 整目录移走 |
| `~/.omp/agent/skills/<name>/` | 安装器（仅仓库 `skills/` 里带的） | 逐个移走，别动用户原有 skill |
| `~/.omp/agent/AGENTS.md` | 安装器追加托管块 | 删托管块；文件原本不存在则删文件 |
| `~/.omp/agent/hooks/pre/guards.ts`（或 `omp-guards.ts`） | 适配卡可选的「门」 | 见 §3.2 / §3.3 |
| `~/.omp/agent/hooks/post/*.ts` | 适配卡可选的「门」 | 同上 |
| `~/.omp/agent/hooks/allow/DELETE-ALLOW.txt` | 门机制的放行清单 | 与门一起删 |
| `~/.omp/agent/RULES.md`、`config.yml` | **安装器不写** | 不要删；只回退你自己加过的那一行指针 |

### 3.2 临时关门（保留规则，只停 hook）

omp 的 hook 是**目录自动发现**：`hooks/pre/*.{ts,js}` 和 `hooks/post/*.{ts,js}` 会在启动时被当成 extension 模块加载，`hooks/` 根下直接放文件不会被发现。**没有配置开关**——这是设计，不是遗漏。

做法（二选一，都要重启 omp）：

```powershell
# A. 关一整套：整个 pre 目录改名（最省事，可逆）
Move-Item "$HOME\.omp\agent\hooks\pre" "$HOME\.omp\agent\hooks\pre.disabled-20261102"
# 恢复：改回来
# Move-Item "$HOME\.omp\agent\hooks\pre.disabled-20261102" "$HOME\.omp\agent\hooks\pre"
```

```powershell
# B. 只关一个门：改后缀，发现逻辑只认 .ts / .js
Rename-Item "$HOME\.omp\agent\hooks\pre\guards.ts" "guards.ts.off"
```

判据：**新开一个 omp 会话**，让它跑一条以前会被拦的命令（例如 `powershell -Command "$x=1"`，`powershell-dollar` 门会拦）。不再被拦 = 门没加载。同一会话里改名无效——模块已经 import 过了。

### 3.3 永久关门

删掉门文件本身（先移到暂存目录，见 §2）：

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null
foreach ($f in @("$HOME\.omp\agent\hooks\pre\guards.ts", "$HOME\.omp\agent\hooks\pre\omp-guards.ts", "$HOME\.omp\agent\hooks\allow\DELETE-ALLOW.txt")) {
  if (Test-Path -LiteralPath $f) { Move-Item -LiteralPath $f -Destination $trash -Force }
}
```

- `hooks/log/guard.*.log` 是门自己写的审计日志，删不删都不影响功能；留着可以查历史误拦。
- 删完必须重启 omp。**不要**为了绕过某条规则去改 `guards.ts` 的判据——那等于把门拆了还留着门框。

### 3.4 卸载规则本体

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null

# 1) 规则目录：整个移走（可逆）
$docs = Join-Path $HOME ".omp\agent\AgentRule"
if (Test-Path -LiteralPath $docs) { Move-Item -LiteralPath $docs -Destination $trash -Force }

# 2) 入口文件：只删托管块；文件本来就是安装器建的才整个删
$entry = Join-Path $HOME ".omp\agent\AGENTS.md"
if (Test-Path -LiteralPath $entry) {
  $t = [IO.File]::ReadAllText($entry)
  $stripped = [regex]::Replace($t, '(?s)\r?\n?<!-- BEGIN agentrule:entry v1 -->.*?<!-- END agentrule:entry v1 -->\r?\n?', '')
  $stripped = $stripped.TrimEnd("`r","`n"," ","`t")
  if ($stripped.Length -eq 0) {
    Move-Item -LiteralPath $entry -Destination $trash -Force          # 整份都是托管块 → 删文件
  } else {
    [IO.File]::WriteAllText($entry, $stripped + "`n", (New-Object System.Text.UTF8Encoding($false)))
  }
}
```

```bash
# bash 等价（macOS / Linux / Git Bash）
trash="$HOME/_agentrule-uninstall-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$trash"
[ -d "$HOME/.omp/agent/AgentRule" ] && mv "$HOME/.omp/agent/AgentRule" "$trash/"
entry="$HOME/.omp/agent/AGENTS.md"
[ -f "$entry" ] && sed -i.bak '/<!-- BEGIN agentrule:entry v1 -->/,/<!-- END agentrule:entry v1 -->/d' "$entry"
# sed -i.bak 会在旁边留一个 AGENTS.md.bak；确认内容无误后删掉它
```

`skills/` 里由本仓库带来的 skill，按目录逐个移走（**不要**整个 `skills/` 移走，里面还有用户自己的）：

```powershell
$skills = Join-Path $HOME ".omp\agent\skills"
# 清单来自安装报告；没有报告就只列不改
$installed = @("dispatch", "verify")   # ← 换成你实际装的名字
foreach ($n in $installed) {
  $p = Join-Path $skills $n
  if (Test-Path -LiteralPath $p) { Move-Item -LiteralPath $p -Destination $trash -Force }
}
```

### 3.5 验证已干净

```powershell
$H = $HOME; $fail = 0
function Chk([string]$n, [bool]$c) { if ($c) { "PASS  $n" } else { "FAIL  $n"; $script:fail++ } }
$entry = Join-Path $H ".omp/agent/AGENTS.md"
Chk "omp: AgentRule/ 已移走"        (-not (Test-Path -LiteralPath (Join-Path $H ".omp/agent/AgentRule")))
Chk "omp: 入口无托管块"             ((-not (Test-Path -LiteralPath $entry)) -or (-not (Select-String -LiteralPath $entry -Pattern "BEGIN agentrule:entry v1" -SimpleMatch -Quiet)))
Chk "omp: hooks/pre 无门文件"       (@(Get-ChildItem -LiteralPath (Join-Path $H ".omp/agent/hooks/pre") -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in ".ts",".js" }).Count -eq 0)
Chk "omp: 无 AgentRule 放行清单"    (-not (Test-Path -LiteralPath (Join-Path $H ".omp/agent/hooks/allow/DELETE-ALLOW.txt")))
"FAIL=$fail"
```

```bash
H="$HOME"; fail=0
chk(){ if [ "$2" = "1" ]; then printf 'PASS  %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
[ ! -d "$H/.omp/agent/AgentRule" ] && r=1 || r=0; chk "omp: AgentRule/ 已移走" "$r"
if [ ! -f "$H/.omp/agent/AGENTS.md" ]; then r=1
elif grep -q "BEGIN agentrule:entry v1" "$H/.omp/agent/AGENTS.md"; then r=0
else r=1; fi; chk "omp: 入口无托管块" "$r"
n=$(ls "$H/.omp/agent/hooks/pre/"*.ts "$H/.omp/agent/hooks/pre/"*.js 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && r=1 || r=0; chk "omp: hooks/pre 无门文件（找到 $n）" "$r"
echo "FAIL=$fail"
```

最后一条**行为**验证：新开 omp 会话，`/skills` 里看不到被删的 skill，入口不再注入 AgentRule 段落。

---

## 4 · Codex

### 4.1 落点

| 路径 | 谁写的 | 卸载动作 |
|---|---|---|
| `~/.codex/AgentRule/` | 安装器 | 整目录移走 |
| `~/.codex/skills/<name>/` | 安装器（仅仓库带的） | 逐个移走 |
| `~/.codex/AGENTS.md` | 安装器追加托管块 | 删托管块 |
| `~/.codex/config.toml` `[features] hooks` | 适配卡可选的「门」 | 改回原值（见 §4.2） |
| `hooks.json`（用户级 `~/.codex/hooks.json`，或项目级 `<repo>/.codex/hooks.json`） | 适配卡可选的「门」 | 删文件 |
| `config.toml` `[hooks.state.'<abs>:<event>:<i>:<j>']` | codex 自己写的信任状态 | 删对应段 |

**以 `[hooks.state]` 里出现的绝对路径为准**——那就是 codex 实际读的 `hooks.json`。它可能是项目级的（`<repo>/.codex/hooks.json`），也可能是用户级的（`~/.codex/hooks.json`），以配置里写的那条为准。

### 4.2 临时关门

Codex 有真开关，改一行即可：

```toml
# ~/.codex/config.toml
[features]
hooks = false
```

或者只停某一份 `hooks.json` 的某个事件（codex 自己写的那段，别手改 hash）：

```toml
[hooks.state.'<abs path>/hooks.json:<event>:0:0']
enabled = false
```

`<event>` 用 `[hooks.state]` 里已经出现的那几个（本机是 `pre_compact` / `post_compact` / `session_start`），别自己编。

验证（codex 会读配置并打印生效值）：

```powershell
codex features list | Select-String '^hooks'
# 期望：hooks   stable   false
```

改完要**重开 codex 会话**。注意两件事：

- 门即使 `hooks = true`，新装的 `hooks.json` 在用户批准、codex 写入 `trusted_hash` 之前也**一行都不跑**——这是 codex 的信任门，不是你的配置问题。
- 反过来，`--dangerously-bypass-hook-trust` 是**放开**信任门，不是关门。卸载/回退时永远不要用它。

### 4.3 永久关门

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null
foreach ($f in @("$HOME\.codex\hooks.json")) {
  if (Test-Path -LiteralPath $f) { Move-Item -LiteralPath $f -Destination $trash -Force }
}
```

然后打开 `~/.codex/config.toml`：

1. 把 `[features] hooks` 改回你装之前的值（没装过门就是没有这一行，或 `false`）；
2. 删掉 `[hooks.state.'...hooks.json:...']` 这些段——它们的路径已经不存在，留着只会让 codex 每次启动去校验一个不存在的文件。

### 4.4 卸载规则本体

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null
$docs = Join-Path $HOME ".codex\AgentRule"
if (Test-Path -LiteralPath $docs) { Move-Item -LiteralPath $docs -Destination $trash -Force }

$entry = Join-Path $HOME ".codex\AGENTS.md"
if (Test-Path -LiteralPath $entry) {
  $t = [IO.File]::ReadAllText($entry)
  $s = [regex]::Replace($t, '(?s)\r?\n?<!-- BEGIN agentrule:entry v1 -->.*?<!-- END agentrule:entry v1 -->\r?\n?', '')
  $s = $s.TrimEnd("`r","`n"," ","`t")
  if ($s.Length -eq 0) { Move-Item -LiteralPath $entry -Destination $trash -Force }
  else { [IO.File]::WriteAllText($entry, $s + "`n", (New-Object System.Text.UTF8Encoding($false))) }
}
```

项目级安装还要检查 `<repo>/.codex/hooks.json`：它通常**被 git 跟踪**，删除是一次代码改动，先 `git status` 再决定，别在别人的工作区里顺手删。

### 4.5 验证已干净

```powershell
$H = $HOME; $fail = 0
function Chk([string]$n, [bool]$c) { if ($c) { "PASS  $n" } else { "FAIL  $n"; $script:fail++ } }
$entry = Join-Path $H ".codex/AGENTS.md"
Chk "codex: AgentRule/ 已移走"   (-not (Test-Path -LiteralPath (Join-Path $H ".codex/AgentRule")))
Chk "codex: 入口无托管块"        ((-not (Test-Path -LiteralPath $entry)) -or (-not (Select-String -LiteralPath $entry -Pattern "BEGIN agentrule:entry v1" -SimpleMatch -Quiet)))
Chk "codex: 用户级 hooks.json 不在" (-not (Test-Path -LiteralPath (Join-Path $H ".codex/hooks.json")))
"FAIL=$fail"
```

```bash
codex features list | grep '^hooks'     # 期望 false（若你不再要门）
```

---

## 5 · Claude Code

### 5.1 落点

| 路径 | 谁写的 | 卸载动作 |
|---|---|---|
| `~/.claude/AgentRule/` | 安装器（脚本路径） | 整目录移走 |
| `~/.claude/rules/agentrule/` | 适配卡（最小安装） | 整目录移走 |
| `~/.claude/skills/<name>/` | 安装器 / 适配卡 | 逐个移走 |
| `~/.claude/CLAUDE.md` | 安装器托管块 / 适配卡模板 | 删托管块；整份是安装器建的则删文件 |
| `~/.claude/hooks/agentrule_gates.py`、`agentrule_session.py` | 适配卡「完整安装」 | 删文件 |
| `~/.claude/settings.json` 的 `hooks` 键 | 适配卡「完整安装」 | 删键（见 §5.3） |

### 5.2 临时关门

```json
// ~/.claude/settings.json
{ "disableAllHooks": true }
```

- 这是官方的一键开关（`claude.exe` 里对它的说明：从 settings 里移除 `disableAllHooks` 后重开会话即恢复）。
- 只想这一次不跑：`claude --safe-mode`（关掉全部定制，包括 `CLAUDE.md`、skills、hooks）。
- **不要**用 `--bare` 当关门的办法：它连 `CLAUDE.md` 自动发现一起跳过，等于把规则也关了，测出来的结论是假的。
- 改完**重开会话**；`claude -p` 下配置校验失败是静默忽略的，看不出问题。

### 5.3 永久关门

先备份，再删 `hooks` 键——**只删这个键，其他键一个不动**：

```powershell
$p = "$HOME\.claude\settings.json"
Copy-Item -LiteralPath $p -Destination "$p.before-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
python -c "import json,io; p=r'$p'; d=json.load(io.open(p,encoding='utf-8')); d.pop('hooks',None); json.dump(d,io.open(p,'w',encoding='utf-8'),indent=2,ensure_ascii=False)"
```

```powershell
# 没有 python 时用 PowerShell（-Depth 100 必须写，默认深度会把嵌套配置截断）
$p = "$HOME\.claude\settings.json"
$j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
$j.PSObject.Properties.Remove("hooks")
[IO.File]::WriteAllText($p, ($j | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
```

然后删门脚本：

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null
foreach ($f in @("$HOME\.claude\hooks\agentrule_gates.py", "$HOME\.claude\hooks\agentrule_session.py")) {
  if (Test-Path -LiteralPath $f) { Move-Item -LiteralPath $f -Destination $trash -Force }
}
```

**Schema 陷阱**：`~/.claude/settings.json` 里 `hooks` 写错一个字段，**整份 user settings 会被丢弃**——`permissions`、`model`、`env` 一起失效。所以改完必须用 `claude` 交互模式启动一次，看有没有报错；只看 `-p` 的退出码不算验证。

### 5.4 卸载规则本体

```powershell
$trash = Join-Path $HOME ("_agentrule-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $trash -Force | Out-Null
foreach ($d in @("$HOME\.claude\AgentRule", "$HOME\.claude\rules\agentrule")) {
  if (Test-Path -LiteralPath $d) { Move-Item -LiteralPath $d -Destination $trash -Force }
}

$entry = Join-Path $HOME ".claude\CLAUDE.md"
if (Test-Path -LiteralPath $entry) {
  $t = [IO.File]::ReadAllText($entry)
  $s = [regex]::Replace($t, '(?s)\r?\n?<!-- BEGIN agentrule:entry v1 -->.*?<!-- END agentrule:entry v1 -->\r?\n?', '')
  $s = $s.TrimEnd("`r","`n"," ","`t")
  if ($s.Length -eq 0) { Move-Item -LiteralPath $entry -Destination $trash -Force }
  else { [IO.File]::WriteAllText($entry, $s + "`n", (New-Object System.Text.UTF8Encoding($false))) }
}
```

如果 `CLAUDE.md` 是手工装的（没有托管块、整份是适配卡模板），**整份删掉**——但先确认里面没有用户自己后来加的内容。

### 5.5 验证已干净

```powershell
$H = $HOME; $fail = 0
function Chk([string]$n, [bool]$c) { if ($c) { "PASS  $n" } else { "FAIL  $n"; $script:fail++ } }
$entry = Join-Path $H ".claude/CLAUDE.md"
Chk "claude: AgentRule/ 已移走"      (-not (Test-Path -LiteralPath (Join-Path $H ".claude/AgentRule")))
Chk "claude: rules/agentrule 已移走" (-not (Test-Path -LiteralPath (Join-Path $H ".claude/rules/agentrule")))
Chk "claude: 入口无托管块"           ((-not (Test-Path -LiteralPath $entry)) -or (-not (Select-String -LiteralPath $entry -Pattern "BEGIN agentrule:entry v1" -SimpleMatch -Quiet)))
$j = Get-Content -LiteralPath (Join-Path $H ".claude/settings.json") -Raw | ConvertFrom-Json
Chk "claude: settings 无 hooks 键"   (-not ($j.PSObject.Properties.Name -contains "hooks"))
Chk "claude: 门脚本已删"             (-not (Test-Path -LiteralPath (Join-Path $H ".claude/hooks/agentrule_gates.py")))
"FAIL=$fail"
```

最后**必须**交互启动一次 `claude`：没有 schema 报错，才说明 settings 没被整份丢弃。

---

## 6 · 回退（装完出问题，回到装之前）

回退和卸载的差别：回退要**逐字节等于安装前**，判据是 `before_sha256`；卸载只要求「这套东西不在」。

### 6.1 有脚本备份

```powershell
# $root = 安装时的 --target（默认就是家目录）；$b = 备份目录
$root = $HOME
$b    = Join-Path $root ".backup-20261102-101500"     # ← 换成实际目录
Get-ChildItem -LiteralPath $b -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($b.Length + 1)
  $dst = Join-Path $root $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
  "{0}  {1}" -f (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower(), $rel
}
```

```bash
root="$HOME"; b="$root/.backup-20261102-101500"
( cd "$b" && find . -type f | while IFS= read -r f; do
    rel="${f#./}"; mkdir -p "$root/$(dirname "$rel")"; cp -p "$f" "$root/$rel"
    printf '%s  %s\n' "$(sha256sum "$root/$rel" | cut -d' ' -f1)" "$rel"
  done )
```

输出里每个 hash 必须等于 manifest 的 `before_sha256`。备份目录里**没有**的文件，说明当时是新建的——按 §3.4 / §4.4 / §5.4 删掉，或者直接移进暂存目录。

### 6.2 手工安装的备份

备份是同目录的 `*.before-bootstrap-YYYYMMDD`：

```powershell
Copy-Item -LiteralPath "$HOME\.omp\agent\AGENTS.md.before-bootstrap-20261102" `
          -Destination "$HOME\.omp\agent\AGENTS.md" -Force
```

### 6.3 一个备份都没有

只做**减法**，不要做「重建」：

1. 删托管块（§3.4 里那段正则），入口文件恢复成安装前的样子；
2. 把 `AgentRule/` 和本次新增的 skill 目录移进暂存目录；
3. 明确告诉用户：**哪些文件回不到原样**（列出路径），因为安装时覆盖且没有备份。

不许把这一步说成「已恢复」。

### 6.4 回退成功的判据

三条全中才算成功：

1. 每个还原文件的 hash = `before_sha256`（不是「看起来一样」）；
2. 入口文件没有 `BEGIN/END agentrule:entry v1`；
3. harness 能正常启动，新会话里没有 AgentRule 段落。

任何一条不中：状态写 `BLOCKED` + 清单，**不许写「已恢复」**。回退过程写进 `rollback.log`。

### 6.5 回退之后

- 暂存目录（`_agentrule-uninstall-*`）先留着，至少留到用户确认没问题；
- 如果是因为门误拦才回退：先看误拦命令原文，改命令或改规则，**不要**把回退当成长期方案；
- 重装前重跑一次 `INSTALL.md` 的 PROBE，别在「半装」状态上叠加第二套。

---

## 7 · 三套对照表

| 动作 | omp | Codex | Claude Code |
|---|---|---|---|
| 规则目录 | `~/.omp/agent/AgentRule/` | `~/.codex/AgentRule/` | `~/.claude/AgentRule/` |
| 入口文件 | `~/.omp/agent/AGENTS.md` | `~/.codex/AGENTS.md` | `~/.claude/CLAUDE.md` |
| 临时关门 | `hooks/pre` 目录改名 / 门文件改后缀，重启 | `[features] hooks = false`，重开会话 | `"disableAllHooks": true`，重开会话 |
| 永久关门 | 删 `hooks/pre/*.ts`、`hooks/post/*.ts` | 删 `hooks.json` + `[hooks.state]` 段 | 删 `settings.json` 的 `hooks` 键 + 门脚本 |
| 开关判据 | 文件不存在 + 新会话不拦 | `codex features list` 显示 `false` | 交互启动无 schema 报错 |
| 备份位置 | `<target>/.backup-<ts>/` | 同左 | 同左 |
| 生效时机 | 重启 omp | 重开 codex | 重开 claude |

---

## 8 · 这次没证明什么

- **没在 macOS / Linux 实跑。** 所有 bash 片段只在本机 Git Bash 下按路径验证过逻辑（`/c/Users/...`），没在真 Linux 上跑；Windows 下 `$HOME` 可能为空，用 PowerShell 那段。
- **没在本机实改 `hooks = false`。** `codex features list` 当前输出 `hooks stable true`，与 `config.toml:86` 的 `hooks = true` 一致；「改成 false 后同一命令显示 false」是推断，标记 `[UNVERIFIED]`。改之前先备份 `config.toml`。
- **omp 没有「列出已加载 hook」的命令。** 门的关闭只能靠文件层证明 + 新会话行为验证，做不到「一条命令证明 hook 没加载」。
- **Claude 的 `disableAllHooks` 只从二进制字符串取证**（`claude.exe` 里 86 处，含「从 settings 移除后重开会话」的说明），没在本机把 hook 真装上再关一次。
- **没有实测「漂移文件」的交互流程**，只定义了判据（当前 hash ≠ `after_sha256` → 停）。

---

## 9 · 复现命令（本文的取证）

```powershell
# 三套 harness 的落点是否存在（只读）
foreach ($p in "$HOME\.omp\agent","$HOME\.codex","$HOME\.claude") { "$p`t$(Test-Path $p)" }
foreach ($f in "$HOME\.omp\agent\AGENTS.md","$HOME\.codex\AGENTS.md","$HOME\.claude\CLAUDE.md") {
  if (Test-Path $f) { "$f`t$((Select-String -LiteralPath $f -Pattern 'BEGIN agentrule:entry v1' -SimpleMatch -Quiet))" } else { "$f`tABSENT" }
}

# omp：hook 发现位置（只读）
Get-ChildItem "$HOME\.omp\agent\hooks\pre","$HOME\.omp\agent\hooks\post" -File |
  Where-Object { $_.Extension -in ".ts",".js" }

# Codex：hooks 特性与信任状态
codex features list | Select-String '^hooks'
Select-String -LiteralPath "$HOME\.codex\config.toml" -Pattern '^\[features\]|^hooks\s*=|^\[hooks\.state' 
```

```bash
# Claude：settings 里有没有 hooks 键（只读）
python -c "import json,io;print('hooks' in json.load(io.open('$HOME/.claude/settings.json',encoding='utf-8')))"
```

---

*本文只讲怎么退。怎么装看 `INSTALL.md`，怎么证明装对了看 `verify.ps1` / `verify.sh`，门的设计看 `../protocol/03-gates.md`。*

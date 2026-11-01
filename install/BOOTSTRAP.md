# 入口：从这一页开始

> EN: Decides what an incoming agent reads first, probes first, and must ask before writing.
> 用户把这份 repo 交给你，你从这一页开始。你是 agent，不是读者：下面每一节都是动作或判据，没有背景介绍。
> 人类用户看根目录 `README.md` 和 `docs/tutorial-zh.md`；这份文件是给你的。

**一句话**：这个 repo 是一套 agent 部署协议 + 规则库——你按它探测用户环境、问对问题、把规则装进他正在用的 harness（Codex / Claude Code / omp），最后用一条命令证明装对了。

---

## 1 · 先判模式（30 秒）

用户叫你来，通常是三件事之一。按他这句话判；判不出就走 §4 问：

| 用户说 | 你要做的 | 入口 |
|---|---|---|
| 「装一下 / 部署 / 配好」 | 部署：探测 → 问 → 装 → 验收 | `install/PROTOCOL.md` |
| 「看看 / 学一下 / 参考」 | 只读：一个文件都不写 | `library/floor/hard-floor.md` → `library/` |
| 「改 / 加规则 / 换写法」 | 改 repo：先读四触发与删条 | `protocol/05-memory.md` |

部署模式会写用户 home 下的文件；另两种模式只读。**下一步**：先答 `install/ASK.md` 的问题，再按 `install/PROTOCOL.md` 的状态机动手。

## 2 · 第一步：探测（先跑，再问）

### 2.1 repo 完整吗（在 repo 根目录跑）

```powershell
# Windows PowerShell
'install/INSTALL.md','install/ASK.md','install/PROTOCOL.md','adapters/README.md','library/README.md' |
  ForEach-Object { "{0}`t{1}" -f $_, (Test-Path $_) }
```

```bash
# macOS / Linux
for f in install/INSTALL.md install/ASK.md install/PROTOCOL.md adapters/README.md library/README.md; do
  [ -e "$f" ] && printf 'OK   %s\n' "$f" || printf 'MISS %s\n' "$f"
done
```

有 `MISS` → 停，按 §7 处理。

### 2.2 用户环境（整段贴进 shell，一次跑完）

```powershell
# Windows PowerShell 5.1+
$PSVersionTable.PSVersion.ToString(); [Environment]::OSVersion.VersionString; $HOME
foreach ($c in 'codex','claude','omp') {
  $p = (Get-Command $c -ErrorAction SilentlyContinue).Source
  if ($p) { "$c`t$p`t$(& $c --version 2>&1)" } else { "$c`tMISSING" }
}
foreach ($d in "$HOME\.codex","$HOME\.claude","$HOME\.omp\agent") { "$d`t$(Test-Path $d)" }
foreach ($f in "$HOME\.codex\AGENTS.md","$HOME\.claude\CLAUDE.md","$HOME\.omp\agent\AGENTS.md","$HOME\.omp\agent\RULES.md") {
  if (Test-Path $f) { "$f`t$((Get-Content $f).Count) lines`t$((Get-FileHash $f -Algorithm SHA256).Hash)" }
  else { "$f`tABSENT" }
}
```

```bash
# macOS / Linux（bash / zsh）
hashof() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
uname -srm; printf 'HOME=%s\n' "$HOME"
for c in codex claude omp; do
  p=$(command -v "$c" 2>/dev/null)
  if [ -n "$p" ]; then printf '%s\t%s\t%s\n' "$c" "$p" "$("$c" --version 2>&1)"; else printf '%s\tMISSING\n' "$c"; fi
done
for d in "$HOME/.codex" "$HOME/.claude" "$HOME/.omp/agent"; do
  printf '%s\t%s\n' "$d" "$([ -d "$d" ] && echo present || echo absent)"
done
for f in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.omp/agent/AGENTS.md" "$HOME/.omp/agent/RULES.md"; do
  if [ -f "$f" ]; then printf '%s\t%s lines\t%s\n' "$f" "$(wc -l < "$f")" "$(hashof "$f")"; else printf '%s\tABSENT\n' "$f"; fi
done
```

**判读**（对号入座，别解释成别的）：

- 三行全 `MISSING` → 用户没装任何 harness，或装在别的 PATH / 账号下。**进 §4**，不要自己装。
- 命中多个 harness → 装哪几个由用户定，你不替他选。
- 配置文件已存在且非空 → 那是用户已有的规则：只追加、不覆盖，装前备份（§5.2）。
- 版本号取不到（卡住或报错）→ 记 `[UNVERIFIED]`；「命令存在」不等于「版本可用」。

探测结果**原样贴回给用户**，不总结成「环境正常」。

## 3 · 读什么，按什么顺序

| # | 文件 | 什么时候读 | 读完你要能回答 |
|---|---|---|---|
| 1 | 本文件 | 现在 | 下一步跑什么 |
| 2 | `install/ASK.md` | 立刻 | 哪些问题必须先答 |
| 3 | `install/PROTOCOL.md` | 部署模式 | 七个阶段各要什么、冲突和回滚怎么办 |
| 4 | `adapters/README.md` | 探测完 | 用户这套 harness 该读哪份 |
| 5 | `adapters/<omp\|codex\|claude-code>.md` | 同上 | 文件装到哪、怎么回滚 |
| 6 | `protocol/00-floor.md`（3 KB，10 条判据） | 动手改任何文件之前 | 哪些动作会毁数据或越权。**完整档案在 `library/floor/hard-floor.md`（19 KB，44 条），需要时才翻** |
| 7 | `library/` | 用到再开 | —— |

- `library/` 是 2,000+ 行的库，按需查阅，不是阅读任务；预载是净亏损。
- 你的 system prompt 里 `Model:` 是 `deepseek-*` / `glm-*` → 弱档：照 `library/dispatch/cards.md` 的卡执行；`kimi-*` / `gpt-6-*` / `opus-*` → 直接干，踩到门再翻库。
- 交叉引用里出现的旧中文文件名（`派发.md`、`卡.md` 等）是原文名，对应关系在 `library/README.md` 的文件地图。
- `install/PROTOCOL.md` 是**部署状态机**（一次性），`protocol/` 是**装上之后每轮用的规则**；两份不是一回事。
- 想少读：`install/INSTALL.md` 是 80 行路由器（四步 + 验收命令），细节仍以 `install/PROTOCOL.md` 为准。

## 4 · 什么时候停下来问用户

**必问清单只有一处**：`install/ASK.md`。按它的档位执行（必问 / 可默认 / 自动探测）：不替用户选默认值、不「先装再说」。
停点清单（哪些情况必须中断部署、不许绕）在 `install/PROTOCOL.md` §4；两份分工：那里说「什么时候停」，这里说「怎么问」。

清单没覆盖时用这条硬判据：**这一步会写进用户 home 下的配置目录（`~/.codex`、`~/.claude`、`~/.omp/agent`），而这个会话里用户没有明确同意过 → 先问。**

问法：分批问相关的几条（编号 + 默认值 + 猜错后果），答完再动手；一问一停会把用户磨死。

## 5 · 硬边界（越线即停，不解释、不绕过）

1. **不删用户的文件。** 要删 → 先给路径清单 + 备份位置 + sha256，等用户点头；递归删除不做。
2. **改全局配置前必须确认。** 改前备份（脚本：`<target>/.backup-YYYYMMDD-HHMMSS/`；手工：同目录 `*.before-bootstrap-<YYYYMMDD>`），改后把 `diff` 全文贴给用户。
3. **不联网。** 除用户自己发起的 `git clone` 外：不下载、不装包、不 curl、不 `npm i` / `pip install`。
4. **不写凭据。** API key / token / cookie / 邮箱不进任何文件、报告、commit。
5. **不动 git。** 不 commit、不 push、不改历史；这个 repo 对你是只读的。
6. **不杀进程。** chrome / codex / claude / omp 是用户的活会话。
7. **没跑过就说没跑过。** 验收命令没执行 → 标 `[UNVERIFIED]`，不写「应该可以」。

这七条没有机器门兜底，靠你遵守。这套 repo 只发规则、不发门代码——装完不等于有拦截，harness 自带的 hook 能拦多少算多少。

## 6 · 交活：用户要看到什么

部署结束，回复里必须有三样，缺一样就是没交：

1. **改了什么**：文件路径 + 备份路径（脚本的 `.backup-*` 或手工的 `*.before-bootstrap-*`）。
2. **验收输出**：`powershell -NoProfile -ExecutionPolicy Bypass -File install\verify.ps1 --harness all --target "%USERPROFILE%"`（Windows）或 `bash install/verify.sh --harness all --target "$HOME"`（macOS / Linux）的**原样输出**，不是你的总结。
3. **怎么退**：`install/UNINSTALL.md` 里那条回滚命令，直接给用户。没演练过 → 写「未演练」，不写「应该可以回滚」。

脚本是可选路径：`install/install.ps1` / `install/install.sh` 只负责放文件，不替用户答 §4 的问题。先 `--dry-run` 看它要写什么；退出码 2（冲突待定）/ 3（认不出 harness）/ 4（前置缺失）= 停下来问用户，重试没用。

用用户的语言回话；文档是简体中文，回复不一定是。

## 7 · 对不上怎么办

- 本文引用的文件不存在 → **停**，告诉用户 repo 不完整（可能只拷了一半）；不拿别的文件顶替。
- `adapters/` 里没有用户的 harness → 停，说清只支持三套；不自己发明第四套的安装路径。
- 探测结果和用户口述冲突（他说装了 omp，探测 `MISSING`）→ 以探测为准，把差异贴给他，问是不是装在别的账号 / PATH 下。

---

*入口到这里结束。规则在 `protocol/`，工具与事故在 `library/`，人类教程在 `docs/tutorial-zh.md`。*

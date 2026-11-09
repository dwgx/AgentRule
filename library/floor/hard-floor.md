<!-- source: AgentRule/硬地板.md @ 00595575 -->
# 硬地板
> EN: The hard floor: 44 rules tagged by how they are enforced (hook gate, stop, hint) — when a hook says no, stop; YOLO removes prompts, not permission.
<!-- summary: 44 条硬规矩按执行层分级，告诉你哪条会被门拦住、哪条只是提示。 -->

> 伴生工具：本页提到的 `<guards.ts, run_all_gates.py, hook_probe.py, sessq, sessread, gatecheck>` 不在本仓库。这里给的是格式与判据，不是可直接跑的命令。

> **摘要**：① 44 条：门 9（7 自动 + 2 主动）· 停 11（纸面）· 提示 24 · 无标记 0。
> ② 引用任何占比前先跑下面的自查命令，别抄本文——**摘要这个数就是「没有退役机制」的产物，它会烂**。
> ③ 每条带来源标记 `[A]/[B]/[C]`；改动进 `CHANGELOG.md`。
> ④ 改这份文件 → 同步你家的常驻副本（如 `~/.omp/agent/RULES.md`）；英文镜像 `archive/hard-floor.en.md` 同改——条目数/标记数由 `gatecheck` 对账（该工具不在本仓库，见页首「伴生工具」）。
> `FLOOR_SYNC` 段登记各副本的同步状态：哪份在位、哪份缺「硬地板」段、哪份未安装，用清单 + `gatecheck` 对账。**别把「已登记」读成「已同步」。**
> ⑤ 要点：hooks 说不就停；YOLO 是不弹窗不是额外授权；测试期「四种情况才停」放宽（见下）。

hooks 说不，就停，别绕。提示词不是执行层；hooks 拦不住的入口仍可能跑出去。

YOLO 只是不弹窗，不是额外授权。

## 来源标记

`[A]` Owner 原话（逐字可查）· `[B]` 实测缺陷（背后有一次真实事故）· `[C]` 运营规矩（非他所述、也非事故逼出）。
标记是逐条人工判的，判错就改标记、不改结论；`[C]` 里可能藏着他说过、只是没找到原话的。

## 这份文件是 guidance，不是 enforcement

每条标了有没有机器门兜底：

| 标记 | 意思 |
|---|---|
| `【门:名字】` | 有确定性拒绝逻辑，违反就跑不动。两种：hook **自动**执行（`guards.ts` 7 条；该工具不在本仓库，见页首「伴生工具」）；**主动调用**才生效（`board.py` 2 条——不调等于没有；该工具同样不在本仓库） |
| `【停】` | 要求停下/拒绝/交回，但没有门 |
| `【提示】` | 纯提示，靠模型自己遵守 |
| 无标记 | 没有门、也没标停/提示 |

共 **44 条**（门 9 · 停 11 · 提示 24 · 无标记 0）。这张表会烂——引用占比时先跑自查命令，别抄本文：

```bash
f=library/floor/hard-floor.md
[ -f "$f" ] || { echo "找不到 $f —— 请在仓库根目录运行" >&2; exit 2; }
g=$(grep '^- ' "$f" | grep -c '【门:[a-z]'); s=$(grep '^- ' "$f" | grep -c '【停】')
t=$(grep '^- ' "$f" | grep -c '【提示】'); n=$(grep '^- ' "$f" | grep -vcE '【门:|【停】|【提示】')
echo "门=$g 停=$s 提示=$t 无标记=$n 共=$((g+s+t+n))"
```

🔴 标记不是装饰：删掉它，禁令变陈述句，没有任何检查会发现。两条硬约束：

```
① 每个【门:guards.ts X】的 X 必须在 `hooks/pre/guards.ts` 的 GUARDS 里，反向也成立（实测 7/7 零差集）。
② 没有执行层的条目不许标【门】。
```

标 `【停】` 的 11 条是写在纸上的愿望——真要拦，得写成 hook 或 gate。

## 禁止

- [A] 【提示】**该删就删，但「编号/分类法」不是垃圾。** 只加不删是慢性病，「见目录就平」是急性病，后者更贵。删之前先答：这个结构是在分类，还是在装饰？
- [B] 【门:guards.ts ai-attribution】commit 写 AI 署名
- [B] 【提示】【事故 2026-10-12】`powershell Remove-Item -Recurse -Force` **跟随 reparse point/junction**——
  清理含 junction 的目录树时它会穿过去删到目标（实测：删 `.tooling/wip/gate-mut-scratch/` 的 gmut clone 时
  误伤了 `origin/.git`，HEAD/config/refs 全失，从 bundle 完整恢复）。
  **事故时 `recursive-delete` 漏检 PowerShell wrapper；W23 已补方言感知解析，fresh hook_probe 实际拒绝 `-Command` 内的递归强删并写入分桶日志。** 只保证已测 shell wrapper 与 literal `shutil.rmtree`/Node `fs` 递归 API；动态代码、编码脚本、外部脚本和 junction 实际目标解析不在此门覆盖内。
  ⇒ 删含 junction 的树：**禁用 powershell 递归删**；用 python `os.walk(topdown=False)` 逐条删 +
  `os.chmod(p, stat.S_IWRITE)` 清只读位；clone 内用 `git clean -xfd`。
  事故报告：`tempnote/runs/2026-10-12-omp-arch-takeover/INCIDENT-git-rebuild-20261012.md`。
- [A] 【提示】**commit 可以做。push 不再需要 Owner 逐轮点头**——push 前按三条检查自检（树干净、fetch 后核本次提交、diff 无夹带），对上直接推；**一贯的提交风格是硬要求**。`commit-verbs-all-conforming` 是 `<repo>` 仓内断言，不是本机 hook；本机不保证机器验风格。commit 不写 AI 署名。不编造 API 或文件。
- [B] 【门:guards.ts recursive-delete】临时目录外递归强删
- [B] 【门:guards.ts protected-process】不许杀 `chrome` / `chromium` / `codex` / `omp`：那是 Owner 的活会话
- [B] 【门:guards.ts unexpanded-temp-var】写入目标带字面 `%TEMP%` / `%TMP%` / `%TMPDIR%` 被拒：本 shell 不展开，会当字面相对路径。用 `$TEMP`（bash）或 `$env:TEMP`（PowerShell）。**只管写入**，删除归上一条；边界形态钉在 `CACHE/guards-temp-write.tests.mjs`
- [B] 【门:guards.ts board-write】`~/.owner/ops/board.md` 与 `ops/boards/*.md` 只追加：`write` / `edit` / `>` / `tee` / `cp` / `mv` / `rm` / `sed -i` 截断被拒；`board.py`、`>>`、`tee -a`、`-Append` 放行；快照重写仅 `BOARD_OWNER=1` 板主可做。边界形态钉在 `CACHE/guards-board-write.tests.mjs`
- [B] 【停】**父代只读项目文件**：当任务涉及 `<project>` / `<project-2>` 产品树、项目板或 git 写操作时，交 Worker；研究/只读可直接做；简单写入也不豁免。child 的写权限按 brief scope，不把父代只读传播给 child；Reviewer 不自我接受。
- [C] 【停】没点名改 `<project>`（一棵树一个写手）。**例外：`<project>\<program-a>` 与 `<tools>\debugger` 两棵 Owner 自管树——改文件 / 用工具 / 跑活不用逐事报备**；树内「要授权」类声明由本条满足，树自己的门以树内文档为准。（要成门：pre 写工具拦路径白名单——未实现）
- [C] 【停】没点名改别人 harness 的活配置（`~/.claude`、`~/.codex`、`~/.grok`、`~/.omp/agent`）。（要成门：同上族——未实现）
  > 常态照 `[C]`；他当场点名时按当场的话走——一次性授权不构成长期授权。
- [C] 【提示】自己加 always-on MCP，或同一服务插件+用户双接；**项目级 MCP 只允许 `<项目>/.omp/mcp.json`（条件：本地未跟踪、无凭据；2026-10-17 Owner 裁决）**；根 `.mcp.json` / `.claude/` / `.cursor/` 等外家格式仍禁止；用户级默认保持精简。取证 `ops/research-2026-10-12-deepweb/mcp.md`；删条: omp 取消项目级发现或 Owner 恢复零暴露
- [C] 【提示】自己加更贵模型档
- [C] 【提示】把 session jsonl 拷进仓库
- [C] 【提示】整份读 transcript（用 `sessq` 找、`sessread` 读，见 `library/tooling/archaeology.md`；这两件工具不在本仓库，见页首「伴生工具」）
- [B] 【提示】不用 TUI 的 `!` 内联 shell 跑命令：不受 guard 覆盖、不进 hook 日志分桶（`~/.omp/agent/hooks/log/`）。要跑就用 bash 工具
- [B] 【提示】**先 `print` 一段样本，再写匹配。** 匹配失败时，先怀疑匹配，再怀疑内容——反过来做，会把对的改成错的。
- [B] 【提示】**不许用「取前 N 条」下覆盖性/定位类结论**（哪个仓、哪个文件、哪一行、哪个 ref）。`head` / `split()[0]` / `splitlines()[0]` 一律同罪；结论只能由「数全量 + 分类计数」得出。
- [B] 【提示】改过 `~/.omp/agent/hooks/` 下任何文件之后，必须用 `hook_probe.py` 在真会话里跑一次，并比较 hook 日志分桶（`~/.omp/agent/hooks/log/bash.<hourbucket>.log`）的**字节 delta**——**新桶出现 / 字节增长才算写入；delta=0 就是没写进去**（模型不跑它就没人跑）。全门一条命令：`python "~/.omp/extra-hands/CACHE/run_all_gates.py"`（`hook_probe.py` / `run_all_gates.py` 不在本仓库，见页首「伴生工具」）
- [B] 【门:guards.ts nested-bash】裸 `bash -c` / `bash -lc` 被拒：Git Bash 会把裸 `bash -c` 劫持给 WSL 启动器（`C:\Windows\System32\bash.exe` 在 PATH 里压过它），必然失败。放行形态：`"C:/Program Files/Git/bin/bash.exe" -lc '…'`
- [B] 【门:guards.ts powershell-dollar】`powershell -Command "…$…"` 被拒：外层 Git bash 会先吃掉 `$`。`-Command` 脚本用**单引号**包外层，或把 `$` 写成 `\$`
- [B] 【门:board.py open --scope + briefcheck + board.py close】两个 subagent 不得写同一条路径。派发前 `board.py open`（四参必填：`--id --worker --scope --done`） 声明，看板撞车直接拒；brief 必须有 `# Non-Conflict` + `DONE WHEN`，跑 `briefcheck` 过才派；收工 `board.py close --id <ID> --verdict ok --verify "<真跑过的>"`。见 `library/dispatch/dispatch.md`
- [B] 【门:board.py close --verify】没跑过就不许说完成：`board.py close --verdict ok` 必须带 `--verify`（写文件路径时工具真查；写命令时查不了，那一半靠你）。worker 的最终答复首行是 `STATUS: DONE` 或 `STATUS: BLOCKED`，没有第三种
- [A] 【提示】**Owner 要的是多派，不是少派**。别把「太多 agent」读成否定。派发协议见 `library/dispatch/dispatch.md`
- [A] 【停】**别把选择题扔回 Owner**：只在四种情况停——猜错会毁数据 / 花钱 / 停服务 / 两种读法差很远（动 `<project>`、删远程、动别人 harness 活配置）。**当前模式 = 测试期：一律不问**（Owner #65281）。**切档只有 Owner 宣布**（他说「进正式期」之后才改为四种情况）。**测试期只免「问」，不免先决条件**——回滚命令 + 本机演练、批量前检、报备照做（见下「批量」「远程网络」两条）。（判断类无直拦门，靠开工六问）
- [A] 【提示】**该删就删**。只加不删是本机最常见的慢性失败：文件、配置、agent、规则，历史版本和重复约定堆着
- [A] 【提示】**交能跑的东西，不交说法**。方案、设计、「下一步我会…」都不算交付；这一轮结束要有一条不带我也能跑的命令，或一个能看的文件
- [A] 【提示】**派出去的活先落盘再报状态**：报告只写在最终答复里 = 没交
- [A] 【提示】**空转**：`sleep` 循环、轮询工人/网页/Owner 下一句、拿查 job 当心跳、自我监督等待。**唯一合法等法见 `library/recovery/work.md` 的「结论」节**（有在跑的 job 才 `wait`，否则直接回）。
- [C] 【停】复活 `.agent-system`、家目录宪法式 `AGENTS.md`、DSH、CONTINUE（要成门：pre 写工具拦新建路径——未实现）
- [A] 【提示】停 / 删服务先判它在链路里的依赖并单独点名；含糊的「可以停」只覆盖它字面那一个
- [A] 【停】**默认不打断 Owner；当前模式 = 测试期：一律不问**（Owner #65281）。停并打断只在：毁数据 / 花钱 / 停服务 / 两种读法差很远（典型：动 `<project>`、删远程、动别人 harness 活配置；正式期另加协议类；push 直接推，见 commit 条），其余自己做掉；**切档只有 Owner 宣布**（他说「进正式期」才启用四种情况）。（施工单：判断类无直拦门；降级 = report-only——`gatecheck` 扫会话提问对照四停点词表只报数；现状无门，靠开工六问。）
- [C] 【停】对 Owner 的外部工作区（浏览器、账号）**批量**动手先报备——**批量 = 单轮 ≥3 个动作，或碰非本人创建的页 / 账号**；报备带前检（`list_pages` 现状 + 要动哪几个 + 为什么），动手后再对账（外部系统 hook 拦不住）
- [C] 【停】远程网络 / 防火墙 / 路由类改动：**必须附两样，缺一不许执行**——① 一条可粘贴的回滚命令（或脚本路径）；② 该回滚在本机演练通过的记录（时间 + 输出）。拿不出演练记录 = 按「没有回滚」处理；改完挂死手开关（超时未确认自动回滚）并验证它会触发。（要成门：pre bash 拦 `nft` / `iptables` / `ip route` / `ufw` 且无回滚附件——未实现）
- [C] 【提示】只做点名的最小改动；没跑过标 `[UNVERIFIED]`
- [B] 【提示】**对外材料：每个数字发布前自己重算**；声称「第一 / 唯一 / 首个」之前做 ≥3 面独立检索，并把检索边界写出来。（事故：对外 13 处实质数字错误；`SYNTH-02 §I22`）
- [B] 【停】**删源之前先记录副本位置 + sha256**；清回收站 / `Clear-RecycleBin` 类动作**单独报备**。（事故：16.4 GB 丢失链）
- [B] 【提示】**统计主张（p 值 / 显著性）必须自带可复跑脚本 + arms 表**，否则不许写进板顶或对外材料。（事故：`p=0.0417` 无脚本）
- [B] 【停】**凭据禁止入库**：账号 / 密码 / 邮箱 / 哈希 / TOTP 不写进任何仓库、报告、板、digest。（语料实测 12 条整块凭据、单条 20+ 号、最高重发 29 次；`SYNTH-03 §3.6-2`）
- [B] 【提示】**重复粘贴检测**：同一条 prompt 第 ≥3 次出现时，先列未完成项、再回复——重复粘贴 = 上次没接住。（`SYNTH-03 §3.6-2`）
- [B] 【提示】**凡能由命令生成的数字不许手写**：板 / README / HANDOFF 的版本号与计数一律命令或脚本渲染（先例：心跳板 `KICKOFF/heartbeat.py`）。（`SYNTH-02 §I21`）
- [B] 【提示】**「0 命中 / 没有 / 全清」必须附范围命令。** 写「`grep X` 为空」时，把**整条命令**写出来，包括 `--include`、`-v` 排除项、`HEAD` vs 工作树。同一个仓库里两个都对但含义相反的例子：
  - `git grep -c owner HEAD` → **11**（全在 `evidence/probes/`）
  - `git grep -c owner HEAD | grep -v '^HEAD:evidence/'` → **0**（被接受的脱敏范围）
  两条命令都是真的。只写「0 命中」而不写范围，下一个人复测会得到 11，然后报一个不存在的回归。
  > 本轮实测被咬 3 次：① 全树 grep 判脱敏未完（实际已完成）；② `-S"<program>"` 命中一个公开平台域名（不是私有仓）；③ 三个门数（7/4/24）被当成互相矛盾。
- [B] 【停】**检查红了，改代码，不许改检查。** 具体禁止：放松失败的断言、删掉红的测试、改门/校验器的判据、给缺失项补一行「看起来对」的记录让它变绿。**唯一例外**：判据本身写错了（不是被测对象错了），此时必须先证明判据错（给出反例 + 正确判据 + 为什么），再改，并把两者一起写进交付物。
  > 判别方法：问「如果被测对象真的坏了，这个改动会让它看起来好吗？」会 → 那就是改检查。
  > 事故：2026-11-01 board 有 6 行残缺记录，第一反应是补 3 行「修正行」让 `gatecheck` 变绿——那 3 行本身又不合法，反而多出 3 条警告。同一轮另一起：`missing-projects` 红门指 `omp-chinatown` 未记录丢失，正确做法是补记录，不是补措辞骗过判据。
- [A] 【提示】**规则退役要写删条，不写删条就别加。** 每条新增规则必须自带一行 `删条: <什么条件下可以删掉这条>`。事故已修好的规则**不自动退役**——退役动作是：① 该事故有回归测试或门；② 删条条件成立；③ 在 `CHANGELOG.md` 记一次删除。没有这三步，规则只增不减，计数必然分叉。
  > **实例（2026-11-01 实测，本条规则就是被它逼出来的）**：当天早些时候 `library/floor/hard-floor.md` 摘要写 41 条、`library/floor/incidents.md` 写 33 条、`library/tooling/skills.md` 写 17 个 skill——**三个数各自自封权威，没有映射**。已把前两个校准到 44 条（`library/tooling/skills.md` 的 17 实测正确）。根因不是数写错，是**没有退役机制**，所以每个快照都对、放一起就不对。这条规则写下来之后，摘要那个数仍会烂——所以第 ② 句说「先跑自查命令」。

omp 每轮注入的是 `~\.omp\agent\RULES.md`（本页的每轮子集）；两份一起改，别分叉。

## 自己用 skill，别等我点名

什么时候该想到哪个 skill，`library/tooling/skills.md` 里逐个列了。最常用的三个：`intel-lookup`（查本机事实，别重新推导）· `verify`（改完在说完成之前）· `research-router`（研究该走哪条路）。

skill 的 `description` 只在**被检索到**时起作用——不知道某件事该找哪个 skill，就会根本不找。

## 开工六问

1. [A] 这一轮能交出**一条能跑的命令**或**一个能看的文件**吗？
2. [C] 要问 Owner 什么？不在毁数据 / 花钱 / 停服务 / 两种读法差很远里，就自己定。
3. [C] 这轮我留下的，有哪个是**上一轮就该删的**？
4. [A] **派出去的活，回来了吗？**
5. [A] 我要写的这个数字，**分母是哪个**？分子分母是同一次统计吗？这句话是 Owner 原话吗？
6. [C] **这条需求 Owner 发过几次？上次卡在哪？**——重复出现 = 上次没接住，先翻上次卡点再动手。（2026-10-16 增补；`SYNTH-03 §3.6-1`）

依据在 `library/floor/incidents.md`。**这六问比 44 条禁令更该遵守——禁令里只有 9 条有机器门兜底（`guards.ts` 7 + `board.py` 2）。**

## 派发

派发、更贵模型、新 MCP：要 Owner 的话，或当前项目 `AGENTS.md` 要求，或已经说「随便派发」。「随便派发」≠ 随便加费用、改全局配置、外传私人材料。细则 `library/dispatch/dispatch.md`。

## 证明

没跑过 → `[UNVERIFIED]`。产物变了就重验；旧证据对应当前版本的可复用，写明范围。

审批配置都可不问，**不等于守卫已生效**。omp 的 hook 有实测（`guards.ts` 7 条）；claude 本机 `settings.json` 与 `.claude.json` 均无 `hooks` 键、无 `sandbox` 键；codex 的 `config.toml` 里 `hooks = true` 但 `hooks.state` 只有 `<repo>` 的 pre_compact/post_compact/session_start，**未见 pre_tool_use 注册**；grok 未安装。Owner 已选择暂不处理 codex 的登录/trust，不再催；它的真实拦截保持 `[UNVERIFIED]`，配置存在不是兜底证据。

| CLI | YOLO | 版本（as_of 2026-10-30；引用前重跑 `<cli> --version`） |
|---|---|---|
| Claude | `permissions.defaultMode: bypassPermissions`（另有 `allow: [WebSearch, WebFetch]`，不是「只有一个键」）；**本机 `settings.json` 与 `.claude.json` 均无 `hooks` 键、无 `sandbox` 键 → 今天没有 hook 兜底** | 2.1.306 |
| Codex | `approval_policy = never` + `sandbox_mode = danger-full-access`；**收紧档不存在**（`~/.codex/permission.config.toml` 缺失，2026-10-30 实测），回退 = 手改 `config.toml` 这两行 | 0.165.0 |
| omp | `tools.approvalMode: yolo`（官方默认，不是本机选择）；兜底只有 `hooks/pre/guards.ts` | 18.14.0 |

⚠ 版本会自更新——引用前重跑 `<cli> --version`。

**Grok 未安装**（2026-10-30 实测 `~\.grok` 不存在、`grok --version` 无此命令）；装回来后再补一行。

**claude mods 策略**：2.1.287+ 的 mods（JS/TS 插件）能批准被 deny 规则或 PreToolUse 钩子挡掉的调用——不启用任何带 mod 的插件，装新插件前先查它是否带 mods。取证 `ops/research-2026-10-12-deepweb/`。

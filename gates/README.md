# 门夹具

> EN: Twenty fixtures and three reference judges you can run; one flag makes a gate go red.

这页回答一个别人只肯陈述、不肯演示的问题：**「有门」这句话，能不能被复跑？**

这里没有 harness、没有 hook、没有日志。只有三样东西：20 条输入、三道门的纯函数判据、一个逐条对答案的脚本。跑完你会拿到一个数字和两个退出码；改坏一行判据，数字会变。

同类项目里没人给这个 —— 我们给。

## 跑

```text
$ python gates/run.py
[fixtures] 20 rows / 3 gates: ai-attribution, recursive-delete, unexpanded-temp-var
PASS  rd-01   recursive-delete     expect=ALLOW  got=ALLOW
PASS  rd-02   recursive-delete     expect=DENY   got=DENY
PASS  rd-03   recursive-delete     expect=DENY   got=DENY
PASS  rd-04   recursive-delete     expect=DENY   got=DENY
PASS  rd-05   recursive-delete     expect=DENY   got=DENY
PASS  rd-06   recursive-delete     expect=DENY   got=DENY
PASS  rd-07   recursive-delete     expect=ALLOW  got=ALLOW
PASS  rd-08   recursive-delete     expect=DENY   got=DENY
PASS  rd-09   recursive-delete     expect=DENY   got=DENY
PASS  ut-01   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-02   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-03   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-04   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-05   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-06   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ai-01   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-02   ai-attribution       expect=DENY   got=DENY
PASS  ai-03   ai-attribution       expect=DENY   got=DENY
PASS  ai-04   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-05   ai-attribution       expect=ALLOW  got=ALLOW
[summary] match 20/20
[verdict] 夹具与判据一致 (exit 0)
```

```text
$ python gates/run.py --mutate
[fixtures] 20 rows / 3 gates: ai-attribution, recursive-delete, unexpanded-temp-var
[mutate] recursive-delete: is_under_temp() 恒真：所有删除目标都当成在 temp 里
PASS  rd-01   recursive-delete     expect=ALLOW  got=ALLOW
FAIL  rd-02   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 典型命中：temp 之外的递归强删
FAIL  rd-03   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 边界：先归一化再比前缀，"/tmp/.." 不是字符串前缀匹配
PASS  rd-04   recursive-delete     expect=DENY   got=DENY
FAIL  rd-05   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：PowerShell 别名 + -Recurse -Force
FAIL  rd-06   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：脚本体里的 shutil.rmtree，命令词是 python
PASS  rd-07   recursive-delete     expect=ALLOW  got=ALLOW
FAIL  rd-08   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 混合目标：一个目标在 temp 内不算数，逐目标判
FAIL  rd-09   recursive-delete     expect=DENY   got=ALLOW  rule=-  span=-  why=floor#2 方言：cmd.exe 的 rd /s /q
PASS  ut-01   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-02   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ut-03   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-04   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-05   unexpanded-temp-var  expect=DENY   got=DENY
PASS  ut-06   unexpanded-temp-var  expect=ALLOW  got=ALLOW
PASS  ai-01   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-02   ai-attribution       expect=DENY   got=DENY
PASS  ai-03   ai-attribution       expect=DENY   got=DENY
PASS  ai-04   ai-attribution       expect=ALLOW  got=ALLOW
PASS  ai-05   ai-attribution       expect=ALLOW  got=ALLOW
[summary] match 14/20
[verdict] 变异被抓到：6 条 FAIL (exit 1)
```

注意 `rd-04` 在变异下仍然是 `PASS`：变异只改「在不在 temp 里」这一条判据，相对路径归另一条判据管。**变异要窄**，否则红了也不知道红在哪。

四行命令，覆盖四种状态：

| 命令 | 你要看到的 | 退出码 |
|---|---|---|
| `python gates/run.py` | `match 20/20` | `0` |
| `python gates/run.py --mutate` | 至少 1 条 `FAIL` | `1` |
| `python gates/run.py --mutate=all` | 三道门依次改坏，9 条 `FAIL` | `1` |
| `python gates/run.py --verbose` | 每条 `PASS` 后面跟 `why` | `0` |

**`--mutate` 退出 `1` 是成功，不是失败。** 它在问：把判据改坏一条，夹具集抓不抓得到。抓不到会退 `3`，那才是真失败 —— 说明这套夹具只会绿，等于没有。这个 `3` 是故意留的：**只会绿的门是假门**（[`../protocol/03-gates.md`](../protocol/03-gates.md) 第 4 节）。

`--mutate` 改的是**实现**（`reference.py` 里的一个常量或一个函数），不是 `expect` 列。改 `expect` 只能证明「我改了预期」，改实现才能证明「夹具盯着判据」。

## 夹具怎么读

`fixtures.tsv`，TAB 分隔，`#` 开头是注释。五列：

| 列 | 含义 |
|---|---|
| `id` | `rd-` / `ut-` / `ai-` 加两位序号；`FAIL` 行里认它 |
| `gate` | 门 id，和 [`../SECURITY.md`](../SECURITY.md) 那张 7 行表逐字一致 |
| `expect` | 只有 `ALLOW` / `DENY`；`DENY` 对应门的退出码 `2` |
| `payload` | 按门分三种：一条 shell 命令串 / 一个写入目标路径 / 一条 commit 信息 |
| `why` | 这条为什么该这样判；前缀 `floor#N` 指 [`../protocol/00-floor.md`](../protocol/00-floor.md) 第 N 条 |

`payload` 里的 `<NL>` 表示换行 —— commit 信息是多行的，而 TSV 的列分隔符是 TAB，行分隔符是换行，直接写换行会把一条夹具拆成两条。

20 条的分布：`recursive-delete` 9 条、`unexpanded-temp-var` 6 条、`ai-attribution` 5 条。每道门都有放行侧、命中侧和至少一条边界。

## 判据原文与逐词判定

`recursive-delete` 和 `ai-attribution` 的判据原文抄自 [`../protocol/00-floor.md`](../protocol/00-floor.md)，一个字没改。`unexpanded-temp-var` 不是地板里的独立一条，它的判据原文在 [`../SECURITY.md`](../SECURITY.md) 的门表第 6 行。下面的表说明这个参考实现把哪些词变成了代码、哪些词没变成代码。

### `recursive-delete` — 第 2 条

> **删除先算代价。** 临时目录之外不做递归强删；删含链接点（junction / reparse point）的树逐条删；删源之前先记副本位置和 sha256；清回收站单独报备。

| 词 | 可判 | 怎么判 |
|---|---|---|
| 临时目录 | 可判 | `/tmp`、`/var/tmp`、`/private/tmp` 三个绝对根，加 Windows 用户 temp 的形状；归一化后比前缀 |
| 外 | 可判 | 归一化后做前缀比较，不是字符串包含 |
| 递归 | 部分 | 只认已测方言：`rm -r`、`Remove-Item -Recurse`、`rd /s`、`del /s`、`shutil.rmtree`（只认字面量第一个参数）；运行时拼出来的命令不可判 |
| 强删 | 可判 | `-f` / `-Force` / `/q` 这类开关；`force:true` 属于 JS 方言，本实现没有 |
| 不做 | 可判 | 命中即拦，没有警告档 |

### `unexpanded-temp-var` — 第 3 条的机器侧

> **凭据不入库。** 账号、密码、邮箱、哈希、TOTP 不写进任何仓库、报告、看板、digest，包括「只写一次」的。

这条规则本身讲凭据；`unexpanded-temp-var` 是同一类「变量没展开就被当成字面量」的故障，判据原文是**写入目标里出现字面 `%TEMP%` / `%TMP%` / `%TMPDIR%`**。

| 词 | 可判 | 怎么判 |
|---|---|---|
| 写入目标 | 部分 | 这个参考实现只吃 `kind=write` 的 `path` 字段；重定向 `>`、`-o`、`cp` 的目标位都不在这里判 |
| 字面 | 可判 | 字符串里真有 `%TEMP%` 这三个字符，不是展开后的路径 |
| `%TEMP%` / `%TMP%` / `%TMPDIR%` | 可判 | 精确名单，大小写不敏感；`%TEMPDIR%` 不在名单里 |
| 出现 | 可判 | 任意位置：前缀、中段、结尾都算 |

### `ai-attribution` — 第 5 条

> **commit 不写 AI 署名。** 提交信息里不出现模型名、工具名、「Generated with」这类行。

| 词 | 可判 | 怎么判 |
|---|---|---|
| 提交信息 | 可判 | `kind=commit` 的 `message` 字段；报告正文、issue 正文不归它管 |
| 模型名 / 工具名 | 部分 | 只认登记过的 13 个 token（claude / codex / copilot / cursor / gpt / …）；新模型不进名单就漏 |
| 「这类行」 | 部分 | 只认三种形态：横幅（`Generated with …`）、trailer（`Co-Authored-By:` 等五个键）、工具邮箱域（`@anthropic.com` 等）；换个写法就漏 |

## 边界行

边界行 = **按另一种读法会改判的行**。一条都不写，等于没看过判据。

| # | 另一种读法 | 哪条夹具会翻 | 本实现选哪边、为什么 |
|---|---|---|---|
| 1 | 「临时目录」读成「路径里有 `tmp` 字样」 | `rd-02` 若目标换成 `/home/u/tmp/x` 会翻成放行 | 存绝对根清单；通配符会被名字骗 |
| 2 | 「递归」读成「所有删除」 | 所有普通 `rm file` 都会被拦 | 只拦递归与强制同现；逐条删是规则允许的恢复动作 |
| 3 | 「外」读成字符串前缀 | `rd-03`（`/tmp/../home/u/data`）翻成放行 | 先 `normpath` 再比；字符串前缀是绕过入口 |
| 4 | 相对路径读成「就在 cwd 下，大概率没事」 | `rd-04` 翻成放行 | 选拦：门看不到这次调用的 cwd，解析不出就不算证明 |
| 5 | 「解析不出目标」读成「放行」 | 未展开变量、glob 会漏 | 选拦（fail-closed）；门的失败方向必须是拦，不是放 |
| 6 | 「temp 变量」读成「任何 `%VAR%`」 | `ut-06`（`%TEMPDIR%`）翻成拦 | 选精确名单；宽名单会拦到正常文件名 |
| 7 | 「写入目标」读成「整条命令」 | 只读的 `grep -o '%TEMP%'` 会被拦 | 只判 `kind=write`；真实误伤记录就是这么来的 |
| 8 | 「字面」读成「展开后的 temp 路径也算」 | `ut-02` 翻成拦 | 选放：判的是没展开的字符，不是它最终落到哪 |
| 9 | 「署名」读成「任何 `Co-Authored-By`」 | `ai-05`（人类 co-author）翻成拦 | 只拦工具名单上的值；人类的 co-author 是正常协作 |
| 10 | 「署名」读成「正文里出现模型名」 | `ai-04` 翻成拦 | 只判 trailer 与横幅行；讲这件事的文档不该被自己的门拦 |

改任何一条读法，都要先改夹具、再改实现 —— 反过来就是「改检查让对象变绿」。

## 这套夹具不证明什么

这一段比上面所有段落都重要。

1. **不证明你机器上装了门。** 这里是纯函数，没有执行位置、没有调用点、没有退出码 `2`。门只有挂进 harness 的调用前钩子才有强制力；挂法见 [`../adapters/README.md`](../adapters/README.md)。
2. **不证明参考实现（`guards.ts`，1,299 行）的行为。** 那份代码和这三个函数不是同一份。夹具证明的是「这 20 条输入下判据稳定」，不是「那份实现也对」。
3. **只覆盖 3 道门。** `protected-process`、`nested-bash`、`powershell-dollar`、`board-write` 没有参考实现，也没有夹具。7 道门的登记表在 [`../SECURITY.md`](../SECURITY.md)。
4. **覆盖的是方言子集。** JS `fs.rm(…,{recursive:true})`、`find -delete`、`xargs rm`、`bash -c "rm -rf"`、junction / reparse point、符号链接、真实 cwd —— 都没覆盖，全都会漏。
5. **20 条不是对抗样本。** 想绕过的人能写出第 21 条让它全绿。夹具证明的是「已知形态判得对」，不是「绕不过」。
6. **不证明误伤率。** 没有真实调用日志做分母；「拦对了」和「拦多了」在这套夹具里长得一样。
7. **`--mutate` 只证明这 3 处改坏会被抓到。** 把分词器的引号处理删掉，只有 `rd-07` 会红；把 `Signed-off-by` 加进 trailer 名单，只有 `ai-04` 会红。变异是抽样，不是证明。
8. **判据是这套夹具作者的读法。** 10 条边界行每一条都能换个读法；换了就要明说，别假装判据是客观的。

**一句话**：这里能证明的是「三道门的判据是**可复跑**的，并且**能红**」；不能证明的是「你的环境因此安全了」。

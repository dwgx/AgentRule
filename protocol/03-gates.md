<!-- source: ops/oss/08-REPO-TREE.md · 派生自 library/floor/hard-floor.md, library/floor/incidents.md -->
# 门

> EN: What a gate is made of, and the smallest pseudocode that can go red.

门 = **在工具调用执行之前**，对这次调用的参数做一次判定：违反判据就拦，不违反就放。三个词先钉死：**门**有执行位置和退出码；**规则**写在纸上，靠模型自觉；**检查**事后跑，管已经发生的事。三者都要，不能互相冒充——规则冒充门，读者会以为有强制力；门冒充检查，坏动作已经执行完了。一道门只判一条规则：塞五条进去，红了不知道改哪条，日志里也分不清。

## 1. 四样缺一不可

| 要素 | 判据 |
|---|---|
| 输入 | 一次调用的**原始参数**：命令串、写入路径、写入内容。不是模型对这次调用的自述 |
| 判据 | 纯函数：`matches`（归不归我管）+ `violates`（违没违反）。只读参数，不读意图，不调模型 |
| 放行 / 拦截 | 放行什么都不做，退出 `0`；拦截打印**哪条规则 + 命中哪一段 + 一条改法**，退出 `2` |
| 退出码 | `0` 放行 · `2` 拦截 · `1` 门自己坏了。**坏了也拦**，不静默放行；harness 只认 `2` 时按 `2` 退 |

## 2. 最小伪码

```
gate <name>(call) -> decision:
    if not matches(call):             # 不归这道门管
        return ALLOW                  # exit 0
    hit = violates(call)              # 纯函数，只读 call
    if hit:
        return DENY(rule, span, fix)  # 打印三样；exit 2
    return ALLOW                      # exit 0
```

`DENY` → **不执行这次调用**，把理由原样交给模型；`ALLOW` → 照常执行。**门的覆盖范围就是它的诚实边界**：内联 shell、外部脚本、运行时拼出来的命令不走这个调用点，门看不见——所以 [`protocol/00-floor.md`](00-floor.md) 仍然要人守。

## 3. 两个例子

```
# 例一：拦递归删除（判据原文：临时目录外递归强删）
gate recursive_delete(call):
    if not (is_shell(call) and recursive(call.command) and forced(call.command)):
        return ALLOW                                    # exit 0
    targets = parse_targets(call.command)               # 每个实参 → 绝对路径
    if targets is unknown:
        return DENY("删除", "目标解析不出", "写绝对路径，逐条删")      # exit 2
    if every(t in TEMP_ROOTS for t in targets):
        return ALLOW                                    # exit 0
    return DENY("删除", "临时目录外的递归强删", "逐条删，或先记副本 + sha256")  # exit 2

# 例二：拦凭据入库（判据原文：凭据禁止入库）
gate credential_in_repo(call):
    if not (is_write(call) and under_repo_or_report(call.path)):
        return ALLOW                                    # exit 0
    if call.path in FIXTURE_ALLOWLIST:                  # 白名单在配置里，不在注释里
        return ALLOW                                    # exit 0
    hit = scan(call.text, [PRIVATE_KEY_HEADER, ASSIGNED_SECRET, EMAIL_WITH_PASSWORD, TOTP_SEED, LONG_HEX])
    if hit:
        return DENY("凭据", hit.span, "换成占位符，或读环境变量")      # exit 2
    return ALLOW                                        # exit 0
```

**两处必须写对。** 一是 `recursive` / `forced` 要认**方言**：`rm -rf`、`Remove-Item -Recurse -Force`、`shutil.rmtree`、`fs.rm({recursive:true})` 是同一个动作的四种写法，只认一种就绕过去了。二是 `ASSIGNED_SECRET` 认**赋值形态**（`password = "…"`、`token: "…"`），不认单词本身——否则讲安全的文档会被自己的门拦住；占位符 `<password>`、`$ENV_VAR`、读环境变量必须放行。

## 4. 判据逐词：可判 / 不可判（原文：**临时目录外递归强删** · **凭据禁止入库**）

| 词 | 可判 | 怎么判 |
|---|---|---|
| 临时目录 | 可判 | 绝对路径白名单；大小写与 symlink 解析要钉死 |
| 外 | 可判 | 绝对路径前缀比较，不是字符串包含 |
| 递归 | 部分 | 只认已测方言；运行时拼出的命令不可判 |
| 强删 | 可判 | `-f` / `-Force` / `force:true` |
| 凭据 | 部分 | 只认登记的形态；自创格式不可判 |
| 禁止 | 可判 | 命中即拦，没有警告档 |
| 入库 | 部分 | 写入仓库 / 报告 / 看板可判；外传、同步不可判 |

**边界行**——换个读法就改判的行；一条都没有也要写为什么：

- 「临时目录」读成「路径里有 `tmp` 字样」→ 判定翻转；所以门里存绝对路径清单，不存通配符。
- 「递归」读成「所有删除」→ 逐条删也被拦；本门只拦递归与强制同现。
- 「凭据」读成「任何长串」→ 哈希与构建产物被误拦；本门只认赋值形态与私钥块头。
- 一条边界都没有的判据（例：「commit 信息里有 `Generated with`」）也要写一句「无边界」，并注明判的是哪个字段——不写等于没看过。

**门必须能红。** 写完先做**负控**：一条该拦的样本必须拿到 `2`，一条该放的必须拿到 `0`。**只会绿的门是假门**；分母为 `0`（一个样本都没扫到）时退非 `0`——「检查了 0 个文件，全部通过」是最贵的谎话。日志要能回答「它今天跑过吗」，每次拦截都要能追到规则编号；追不到就是理由写得不够，从没命中过的门要么规则写错，要么没接上调用点。

判据不变，落点随 harness 变：有调用前钩子的挂在钩子上，只有事后检查的退成检查，两样都没有的退成书面规则——**部署报告里必须写明「本机没有机器门」**。落点见 `adapters/`。

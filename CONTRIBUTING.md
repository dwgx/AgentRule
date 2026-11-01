# 贡献指南

> EN: What counts as a contribution here, and what we will not merge.

这个仓库是**协议包**，不是普通代码项目。我们收**规则、事故和适配修复**，不收没有失败证据的「最佳实践」。

## 我们接受

- **事故报告**：真实失败 + 命令/输出 + 代价
- **规则修改**：一条规则 + 一个失败 + 判据 + `删条:` + token 成本
- **安装/适配修复**：harness + 系统 + 版本 + 命令 + 期望/实际 + `VERDICT:`

## 我们不接受

- 没有事故的规则；重复规则；只在单机成立且没有 adapter 说明的规则
- 含凭据、个人路径、未脱敏日志的文本
- 一次 PR 改多条规则，或夹带无关改动

## 写之前

读 [`AGENTS.md`](AGENTS.md) §4、[`protocol/05-memory.md`](protocol/05-memory.md) §3、[`library/README.md`](library/README.md)。

**不要重复它们**；这份文件只讲「提交前要准备什么」。

## 一条规则必须满足

| 项 | 要求 |
|---|---|
| 失败证据 | 链接事故档案，或贴命令输出 |
| 可判 | 能给出一条检查；不能机器判的写「判断规则」 |
| 删条 | `删条: <什么条件下可以删>` |
| token 成本 | 常驻 N 行/字节；只进 library 的写「不预载」 |
| 层级 | `protocol/` / `adapters/` / `library/` / `docs/` 四选一 |
| 去重 | 先 `grep` 现有规则；重复就改现有条目 |
| 数字 | 带分母和日期 |

**层级怎么选**：

- `protocol/` — 换 harness 也不变的判据。**这里每多一行，所有人都要付**（见 [`scripts/budget.py`](scripts/budget.py)）
- `adapters/` — 单家 harness 的差异
- `library/` — 来历、事故档案、操作手册。**按需打开，不预载**
- `docs/` — 人读的教程与案例

**放错层比写错话更难修。**

## 提交

| 改动 | 怎么做 |
|---|---|
| 错字 / 链接 | 直接 PR |
| 规则修改 | 先开「规则提案」issue，再 PR |
| 安装故障 | 开「安装故障」issue，贴 `VERDICT:` 行 |

## PR 前检查

```bash
bash scripts/check-leaks.sh --root .    # 末行必须是 TOTAL: 0
git diff --check                        # 不能有空白错误
python scripts/budget.py                # 改了 protocol/ 就跑，别让总量超 32,768 B
python scripts/check-protocol.py        # 改了 protocol/ 或 manifest.tsv 就跑，末行 FAIL 必须是 0
```

- 改了安装脚本 → 跑 `install/verify.ps1` / `install/verify.sh`，把 `VERDICT:` 行贴进 PR
- 改了规则 → `CHANGELOG.md` 按 MAJOR/MINOR/PATCH 更新，新规则必须带 `删条:`

## 许可是拆开的

- **代码**（`install/*.ps1`、`install/*.sh`、`scripts/*`）：MIT，见 [LICENSE](LICENSE)
- **文档**（全部 `*.md`）：CC BY-SA 4.0，见 [LICENSE-docs](LICENSE-docs)

**注意 ShareAlike**：你提交的文档，别人改写后发布的版本也必须用同一许可。提交即同意按对应许可发布。

没有 CLA。

## agent 可以起草，人必须负责

允许 agent 生成 PR，但提交者要：

1. 贴出用的 prompt
2. 贴出跑过的命令与 `VERDICT:` 输出
3. 声明「我读过 diff」

**责任留在人身上。** 不接受「模型说的」作为理由。

## 审查

**单维护者，best-effort，不承诺固定时限。**

拒绝理由限定为六类：没有事故、重复、不可判、token 膨胀、单家规则没 adapter、含敏感信息。其他理由会说清楚，但可能比较慢。

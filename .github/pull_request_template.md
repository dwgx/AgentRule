## 这个 PR 改了什么

<!-- 一句话。改规则的话，写清是哪一条、在哪一层。 -->

## 为什么

<!-- 规则修改必须有失败证据。贴命令与输出，或链接事故档案。没有证据的「最佳实践」会被关掉。 -->

## 检查

- [ ] `bash scripts/check-leaks.sh --root .` 末行是 `TOTAL: 0`
- [ ] `git diff --check` 干净
- [ ] 改了 `protocol/` → 跑过 `python scripts/budget.py`，总量仍在 32,768 B 以内
- [ ] 改了 `protocol/` → 跑过 `python scripts/check-protocol.py`，末行 `FAIL 0`；改正文就同步 `protocol/manifest.tsv` 的字节 / 行数
- [ ] 改了安装脚本 → 跑过 `install/verify.ps1` / `verify.sh`，`VERDICT:` 行贴在下面
- [ ] 新增规则带了 `删条:`
- [ ] `CHANGELOG.md` 按 MAJOR / MINOR / PATCH 更新了

```
把 VERDICT 行贴在这里
```

## 如果这个 PR 是 agent 写的

- [ ] 我读过 diff
- [ ] 我贴了用的 prompt
- [ ] 我贴了跑过的命令

**责任在人身上。** 「模型说的」不是理由。

# 安装：四步路由

> EN: Routes you through four install steps; it defines none of them, so it cannot drift from PROTOCOL.md.

**这页只做路由。** 每步一句话、一个链接。阶段划分、停点、回滚、状态机全部只有一份，在 [`PROTOCOL.md`](PROTOCOL.md)；本页不复述。两份冲突时以 `PROTOCOL.md` 为准。

## 第一步 · 探测

先跑探测，再开口问。命令在 [`BOOTSTRAP.md`](BOOTSTRAP.md) §2：一段查仓库是否完整，一段查用户的 harness、版本和已有配置。

探测结果**原样贴回**，不总结成「环境正常」。出现 `MISS` 就停，按该文件 §7 处理。

## 第二步 · 回答问题

唯一问题清单是 [`ASK.md`](ASK.md)：12 条，分必问、可默认、自动探测三档。磁盘能查的先查；必问项没答，不许往用户 home 写任何文件；一次最多问 4 条。

## 第三步 · 执行

按 [`PROTOCOL.md`](PROTOCOL.md) 走。**本页不展开任何阶段**——读它，照它做；写盘前的停点、冲突处理、回滚都在那里。

## 第四步 · 验收

在 repo 根目录跑（`--source .` 指回源树）：

```bash
bash install/verify.sh --harness omp --source . --target "$HOME"
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install\verify.ps1 --harness omp --source . --target "$env:USERPROFILE"
```

`--harness` 换成实际装的那套；`all` 只在你三套都装时用。末行必须是 `VERDICT: PASS (exit 0)`：退出 1 = 有 FAIL，退出 2 = 有 SKIP（缺工具或缺基线），都不算过。**原样贴输出**，不写「应该可以」。

它证明装进去的东西能用；逐字节是否与源一致，另跑 `install.ps1 --verify`（看 `[summary] ok N  bad 0`）。装完要重开会话才生效。

## 卡住了读哪里

| 症状 | 读哪篇 |
|---|---|
| 探测有 `MISS`，或引用的文件不存在 | [`BOOTSTRAP.md`](BOOTSTRAP.md) §7 |
| 不知道该问什么、用户不回答 | [`ASK.md`](ASK.md) |
| 安装脚本退 2 / 3 / 4 | [`PROTOCOL.md`](PROTOCOL.md) §4 + [`BOOTSTRAP.md`](BOOTSTRAP.md) §6 |
| 不知道装哪套 harness、文件放哪 | [`../adapters/README.md`](../adapters/README.md) |
| 不确定哪些动作会毁数据或越权 | [`../protocol/00-floor.md`](../protocol/00-floor.md)（3 KB，10 条判据）；完整档案 [`../library/floor/hard-floor.md`](../library/floor/hard-floor.md)（19 KB） |
| 装完模型没读到规则 | 先重开会话；仍不对，查 [`../adapters/README.md`](../adapters/README.md) 里的入口路径 |
| 要卸载 / 升级 | [`UNINSTALL.md`](UNINSTALL.md) / [`UPGRADE.md`](UPGRADE.md) |

## 一条硬提醒

Codex 的 `project_doc_max_bytes` 默认 **32768**：`AGENTS.md` 超过 32,768 字节会被**静默截断**，不报错，模型只是看不到后半段。

所以入口文件只放指针（约 800 B），规则分篇放进 `AgentRule/`，按需读。**不要把规则拼成单文件**；用户已有的巨型入口，先拆成指针再装。

## 边界

- 本页不定义阶段、不写回滚——那些只有一份，在 `PROTOCOL.md`。
- 脚本是可选路径：它只放文件，不替用户回答 `ASK.md` 的问题。
- 装到哪、怎么退：看 `PROTOCOL.md` 与 `UNINSTALL.md`。

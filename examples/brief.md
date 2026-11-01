# 派发 brief（示例）

> EN: What a filled dispatch brief looks like, field by field.

这是 `protocol/02-dispatch.md` §2 那份模板**填好之后**的样子。下面围起来的那一段，就是工人收到的全部输入——工人看不到父代的历史，也看不到别人的 brief，所以 brief 必须自足。

两段可选没写，原因如下：

- `# 口径对表`：这份 brief 没有引用用户原话。引用了就必须带日期和出处。
- `# Stop-Search`：这是实现类任务，`DONE WHEN` 已经是终点；探索类任务才需要早停判据 + 调用预算 + 逃生舱。

## 样例

```text
YOU ARE THE WORKER.
board: AR-021

# Report
C:/work/agentrule/reports/AR-021.md

# Target
C:/work/agentrule/library/ —— 把这一层下全部 *.md 里的链接目标改成相对路径：`[文字](路径)` 从当前文件所在目录出发要能打开（跨目录用 ../）。
旧写法有两种：中文文件名当目标（如 派发.md），以及 `01-` 这类带数字编号的旧目录前缀（后接 floor、dispatch 等书架名）。
改完这两类命中都必须是 0 行。

# Needs
write, bash, read

# Env-Claims
- 仓库根 = C:/work/agentrule，`git rev-parse --show-toplevel` 实测 2026-11-02。
- 本机 `grep -P` 不可用，用 `grep -E`。[实测 2026-11-02]

# Non-Conflict
- C:/work/agentrule/library/

# Change
允许：改 Markdown 链接目标；把中文文件名引用换成新树路径。
禁止：改正文措辞；新增文件；动 protocol/、install/、adapters/、examples/（别的工人占着）；commit。
判据：改完的每个 `[文字](路径)`，从它所在文件出发能打开。

# Acceptance
DONE WHEN: `cd C:/work/agentrule && ! grep -rnoE '\]\([^)]*[一-龥]\.md\)' library/ && ! grep -rnE '0[1-6]-(floor|dispatch|recovery|tooling|machine|specialist)/' library/ && echo LINKS-OK`
退出码 0，stdout 最后一行是 LINKS-OK。报告里贴这条命令的原样输出。
```

## 这份 brief 为什么这样填

| 段 | 判据 | 这里怎么做的 |
|---|---|---|
| `# Report` | 绝对路径，父代读得到；放在最前 | `C:/work/agentrule/reports/AR-021.md`；它前面没有任何带「报告 / report」字样的段 |
| `# Target` | 路径写死，不写「相关目录」 | 写了 `library/` 全路径，并把完成状态写成两类命中为 0；链接的判据是「从文件所在目录出发能打开」 |
| `# Needs` | 工具清单写死 | `write, bash, read`——要落盘就必须给 `write`；派只读的工人，报告得由父代落盘 |
| `# Env-Claims` | 环境断言只写这段，逐条带日期 | 两条都标了实测日期；没测过的写 `[未验证]` |
| `# Non-Conflict` | 只列**写**路径 | 只列 `library/`。读哪里都行，不用列；列父目录会连带占住子目录 |
| `# Change` | 允许什么、禁止什么 | 禁止项点名了别的工人占的目录，省得撞车后再回滚 |
| `DONE WHEN` | 一条命令、可复跑、能红 | 用 `!` 反转 grep 的退出码：命中就退 1，两类都 0 行才打印 LINKS-OK |

## 三个常见填错

1. **报告路径写相对路径。** 工人按自己的 cwd 解析，写到你看不见的地方 = 这活没交。
2. **`DONE WHEN` 写形容词。** 「链接都改对了」不算；「两条 grep 都 0 命中」才算。还要写全 cwd、期望退出码、期望输出。
3. **`# Non-Conflict` 列父目录。** 列 `C:/work/agentrule/` 会把别人要写的子目录一起占住；列到你要写的那一层。

## 生产环境还要加什么

- **自审四段**（A 早产出 → B 反驳 → C 机械验证 → D ≤14 行小结），见 `library/dispatch/dispatch.md` §自审。
- **弱档模型**（system prompt 里 `Model:` 是 `deepseek-*` / `glm-*`）：把 `library/dispatch/cards.md` 里对应的卡粘进 `# Change` 前面。
- **填完过一遍检查器**：`briefcheck.py` 是参考实现，**不在本仓库**（判据见 `protocol/02-dispatch.md`）；自己实现一个，或按判据人工过。模板原样复制会被拒（`Non-Conflict` / `DONE WHEN` / `Report` / `Needs` 四项），这是设计意图——尖括号必须换成真值。

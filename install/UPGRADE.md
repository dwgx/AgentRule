# 升级与漂移检测

> EN: How to tell whether your installed copy is stale, and how to upgrade it without losing local edits.

你装的是**快照**：某一天从仓库拷出来的一批文件。上游会继续改，你的副本不会自己变。
这页只回答三件事：**副本旧没旧、旧在哪几份、升级时哪些能直接覆盖、哪些必须人来看。**

**一句话**：每份规则头部带一行戳（版本 + 正文哈希 + 来源路径）；一条只读命令把「已装副本 / 戳 / 当前仓库」三方对一遍，输出 9 种状态；只有 `OK` 不用管，其余各有固定动作。

---

## 0 · 先分清三种「旧」

同一句「和源不一致」可能是三件完全不同的事。混在一起看，永远对不上账：

| 说法 | 实际含义 | 谁造成 | 判据 |
|---|---|---|---|
| 「我装的不是最新」 | 仓库比你装的那版新 | 上游提交 | 仓库文件正文哈希 ≠ 戳里的 `body` → `STALE` |
| 「我这份和仓库不一样」 | 装的是同一版，但字节不同 | 你本地改过 | 重算正文哈希 ≠ 戳里的 `body` → `LOCAL` |
| 「装漏了」 | 仓库有、你目录里没有 | 上次装的是更旧的快照 | 仓库里有戳、`AgentRule/` 下没有 → `MISSING` |

戳的作用就是把这三件事拆开：

- `body=` 是**装的时候长这样**；
- 重算值是**现在长这样**；
- 仓库同名文件是**上游现在长这样**。

三者两两比较，正好得到上表。没有戳，只剩「和源不一致」一句话，等于没有信息。

---

## 1 · 戳的格式

### 1.1 文档戳

一行 HTML 注释，放在文件里：

```text
<!-- agentrule: v=2026.11.0 id=floor body=sha256:3f2a91c0… merge=replace src=protocol/00-floor.md -->
```

| 字段 | 必填 | 含义 |
|---|---|---|
| `v` | 是 | 发布版本，等于仓库 tag 去掉 `v` 前缀（tag `v2026.11.0` → `2026.11.0`） |
| `id` | 是 | 稳定标识。文件改名时 `id` 不变，用来认「还是同一份规则」 |
| `body` | 是 | 正文哈希，算法见 §1.3；`sha256:` 前缀可省略，比较时统一去掉 |
| `merge` | 是 | `replace` = 可整份覆盖；`block` = 只换托管块；`manual` = 永不自动覆盖 |
| `src` | 是 | 仓库内相对路径，用来找上游对照文件 |

**位置规则**（三条，检测器按同一套实现）：

1. 普通 Markdown：**第一个非空行**。
2. 带 YAML front-matter 的文件（`SKILL.md`）：front-matter 结束的 `---` **之后**第一个非空行。放前面会把 front-matter 弄坏。
3. 一行写完，不换行。注释体里不要出现 `-->`，会提前结束注释。

### 1.2 入口块戳

入口文件（`AGENTS.md` / `CLAUDE.md`）只改托管块，戳放在 `BEGIN` 行的下一行：

```text
<!-- BEGIN agentrule:entry v1 -->
<!-- agentrule: v=2026.11.0 id=entry-omp merge=block -->
规则书在 `~/<harness>/AgentRule/`。不要整目录预载，先读 `AgentRule/README.md`。
<!-- END agentrule:entry v1 -->
```

标记里的 `v1` 是**标记格式版本**，不是发布版本；发布版本在下一行的戳里。两者别混。

托管块**不带 `body`**：它是一段片段，不独立成文件，没有对照物。**块只比版本号**。
块外的内容是用户的，升级永远不碰。

### 1.3 正文哈希

```text
body = sha256( 文件字节 → 去掉戳行 → CRLF 归一为 LF → 不 strip 行尾空白 )
```

三个细节，少一个就对不上：

1. **去掉戳行再算**。戳里存自己的哈希是自指，永远算不出来。
2. **CRLF 归一为 LF**。否则 `core.autocrlf` 一换，整库哈希全变。
3. **不 strip 行尾空白**。strip 会把「编辑器自动删了行尾空格」这种真实改动藏掉。

参考实现（发布侧和检测侧必须用同一份）：

```python
import hashlib, re
S = re.compile(rb"^<!--[ \t]*agentrule:[ \t]*.*?[ \t]*-->[ \t]*$")

def stamp_index(lines):
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].strip() == b"---":      # YAML front-matter
        j = i + 1
        while j < len(lines) and lines[j].strip() != b"---":
            j += 1
        i = j + 1
        while i < len(lines) and not lines[i].strip():
            i += 1
    return i if i < len(lines) and S.match(lines[i]) else None

def body_sha(data: bytes) -> str:
    lines = data.replace(b"\r\n", b"\n").split(b"\n")
    i = stamp_index(lines)
    if i is not None:
        lines = lines[:i] + lines[i + 1:]
    return hashlib.sha256(b"\n".join(lines)).hexdigest()
```

它只删**位置规则允许的那个戳行**，正文里引用戳格式的示例不受影响。

### 1.4 版本与 tag

- 版本号 `YYYY.MM.N`，与 git tag `vYYYY.MM.N` 一一对应。
- 同一仓库里**所有带戳的文档必须是同一个 `v`**。不一致 = 发布没盖全，检测器报 `VERSION-SPLIT`。
- `v` 的唯一用途是取三方合并的 base（§3.1）和给入口块比新旧；**判断过期以哈希为准**，不以版本号为准。

---

## 2 · 对账：一条只读命令

检测器只读：不写文件、不备份、不联网、不改戳。它只打印一张表和一个退出码。

### 2.1 跑法

把下面这段代码原样贴进 shell（`<home>` 是 harness 目录，`<repo>` 是仓库 checkout）。

**bash / zsh / Git Bash：**

```bash
REPO="$HOME/agentrule"                      # 改成你 clone 的仓库路径
python - "$HOME/.omp/agent" "$REPO" <<'PY'
import hashlib, os, re, sys

HOME = os.path.expanduser(os.environ.get("AR_HOME") or (sys.argv[1] if len(sys.argv) > 1 else "~/.omp/agent"))
REPO = os.environ.get("AR_REPO") or (sys.argv[2] if len(sys.argv) > 2 else None)
REPO = os.path.expanduser(REPO) if REPO else None
if not os.path.isdir(HOME):
    print("usage: AR_HOME=<harness home> [AR_REPO=<repo checkout>] python - <<'PY' ...", file=sys.stderr)
    print("not a directory: " + HOME, file=sys.stderr)
    sys.exit(2)
S = re.compile(rb"^<!--[ \t]*agentrule:[ \t]*(.*?)[ \t]*-->[ \t]*$")
F = re.compile(rb"([a-z][a-z0-9_-]*)=(\S+)")
BEGIN = b"<!-- BEGIN agentrule:entry v1 -->"
ENTRY_NAMES = ("AGENTS.md", "CLAUDE.md")
RANK = {"STALE": 0, "LOCAL+STALE": 0, "BAD-STAMP": 1, "UNSTAMPED": 2,
        "MISSING": 3, "UPSTREAM-MISSING": 3, "VERSION-SPLIT": 4, "LOCAL": 5, "OK": 9}

def load(p):
    with open(p, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")

def fields(line):
    m = S.match(line)
    return {k.decode(): v.decode() for k, v in F.findall(m.group(1))} if m else None

def stamp_at(lines):
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].strip() == b"---":          # YAML front-matter
        j = i + 1
        while j < len(lines) and lines[j].strip() != b"---":
            j += 1
        i = j + 1
        while i < len(lines) and not lines[i].strip():
            i += 1
    return i if i < len(lines) and fields(lines[i]) else None

def body_and_stamp(data):
    lines = data.split(b"\n")
    i = stamp_at(lines)
    if i is None:
        return data, None
    return b"\n".join(lines[:i] + lines[i + 1:]), fields(lines[i])

def sha(b):
    return hashlib.sha256(b).hexdigest()

def entry_stamp(data):
    lines = data.split(b"\n")
    for i, line in enumerate(lines):
        if line.strip() == BEGIN:
            for j in range(i + 1, min(i + 4, len(lines))):
                st = fields(lines[j])
                if st:
                    return st
    return None

def repo_version(repo):
    vs = set()
    for dp, _, fs in os.walk(repo):
        for fn in fs:
            if fn.endswith(".md"):
                _, st = body_and_stamp(load(os.path.join(dp, fn)))
                if st and "v" in st:
                    vs.add(st["v"])
    return ",".join(sorted(vs)) if vs else None

def target(home, src):
    return os.path.join(home, src) if src.startswith("skills/") else os.path.join(home, "AgentRule", src)

rows, bad = [], 0
def add(status, rel, note=""):
    global bad
    rows.append((RANK.get(status, 8), status, rel, note))
    bad += status != "OK"

rv = repo_version(REPO) if REPO else None
if rv and "," in rv:
    add("VERSION-SPLIT", "(repo)", rv)

seen = set()
for base in (os.path.join(HOME, "AgentRule"), os.path.join(HOME, "skills")):
    for dp, _, fs in os.walk(base):
        for fn in sorted(fs):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, HOME).replace("\\", "/")
            seen.add(rel)
            body, st = body_and_stamp(load(p))
            if st is None:
                add("UNSTAMPED", rel)
                continue
            if "body" not in st or "src" not in st:
                add("BAD-STAMP", rel, "missing body= or src=")
                continue
            computed, recorded = sha(body), st["body"].replace("sha256:", "")
            local = computed != recorded
            moved = False
            if REPO:
                up = os.path.join(REPO, st["src"])
                if not os.path.isfile(up):
                    add("UPSTREAM-MISSING", rel, "src=" + st["src"])
                    continue
                moved = sha(body_and_stamp(load(up))[0]) != recorded
            add({(0, 0): "OK", (1, 0): "LOCAL", (0, 1): "STALE", (1, 1): "LOCAL+STALE"}[(local, moved)],
                rel, "v=" + st.get("v", "?"))

for name in ENTRY_NAMES:
    p = os.path.join(HOME, name)
    if not os.path.isfile(p):
        continue
    seen.add(name)
    st = entry_stamp(load(p))
    if st is None:
        add("UNSTAMPED", name)
    elif REPO and rv and st.get("v") != rv:
        add("STALE", name, "block v=%s repo v=%s" % (st.get("v"), rv))
    else:
        add("OK", name, "block v=" + st.get("v", "?"))

if REPO:
    for dp, _, fs in os.walk(REPO):
        for fn in sorted(fs):
            if not fn.endswith(".md"):
                continue
            _, st = body_and_stamp(load(os.path.join(dp, fn)))
            if not st or "src" not in st:
                continue
            rel = os.path.relpath(target(HOME, st["src"]), HOME).replace("\\", "/")
            if rel not in seen:
                add("MISSING", rel, "src=" + st["src"])

print("STATUS         FILE  NOTE")
for _, status, rel, note in sorted(rows):
    print(status.ljust(14) + rel + ("  " + note if note else ""))
print()
print("drift: %d of %d need attention" % (bad, len(rows)))
sys.exit(0 if bad == 0 else 1)
PY
```

**Windows PowerShell**（PowerShell 没有 heredoc，用字面 here-string）：

```powershell
$code = @'
import hashlib, os, re, sys

HOME = os.path.expanduser(os.environ.get("AR_HOME") or (sys.argv[1] if len(sys.argv) > 1 else "~/.omp/agent"))
REPO = os.environ.get("AR_REPO") or (sys.argv[2] if len(sys.argv) > 2 else None)
REPO = os.path.expanduser(REPO) if REPO else None
if not os.path.isdir(HOME):
    print("usage: AR_HOME=<harness home> [AR_REPO=<repo checkout>] python - <<'PY' ...", file=sys.stderr)
    print("not a directory: " + HOME, file=sys.stderr)
    sys.exit(2)
S = re.compile(rb"^<!--[ \t]*agentrule:[ \t]*(.*?)[ \t]*-->[ \t]*$")
F = re.compile(rb"([a-z][a-z0-9_-]*)=(\S+)")
BEGIN = b"<!-- BEGIN agentrule:entry v1 -->"
ENTRY_NAMES = ("AGENTS.md", "CLAUDE.md")
RANK = {"STALE": 0, "LOCAL+STALE": 0, "BAD-STAMP": 1, "UNSTAMPED": 2,
        "MISSING": 3, "UPSTREAM-MISSING": 3, "VERSION-SPLIT": 4, "LOCAL": 5, "OK": 9}

def load(p):
    with open(p, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")

def fields(line):
    m = S.match(line)
    return {k.decode(): v.decode() for k, v in F.findall(m.group(1))} if m else None

def stamp_at(lines):
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].strip() == b"---":          # YAML front-matter
        j = i + 1
        while j < len(lines) and lines[j].strip() != b"---":
            j += 1
        i = j + 1
        while i < len(lines) and not lines[i].strip():
            i += 1
    return i if i < len(lines) and fields(lines[i]) else None

def body_and_stamp(data):
    lines = data.split(b"\n")
    i = stamp_at(lines)
    if i is None:
        return data, None
    return b"\n".join(lines[:i] + lines[i + 1:]), fields(lines[i])

def sha(b):
    return hashlib.sha256(b).hexdigest()

def entry_stamp(data):
    lines = data.split(b"\n")
    for i, line in enumerate(lines):
        if line.strip() == BEGIN:
            for j in range(i + 1, min(i + 4, len(lines))):
                st = fields(lines[j])
                if st:
                    return st
    return None

def repo_version(repo):
    vs = set()
    for dp, _, fs in os.walk(repo):
        for fn in fs:
            if fn.endswith(".md"):
                _, st = body_and_stamp(load(os.path.join(dp, fn)))
                if st and "v" in st:
                    vs.add(st["v"])
    return ",".join(sorted(vs)) if vs else None

def target(home, src):
    return os.path.join(home, src) if src.startswith("skills/") else os.path.join(home, "AgentRule", src)

rows, bad = [], 0
def add(status, rel, note=""):
    global bad
    rows.append((RANK.get(status, 8), status, rel, note))
    bad += status != "OK"

rv = repo_version(REPO) if REPO else None
if rv and "," in rv:
    add("VERSION-SPLIT", "(repo)", rv)

seen = set()
for base in (os.path.join(HOME, "AgentRule"), os.path.join(HOME, "skills")):
    for dp, _, fs in os.walk(base):
        for fn in sorted(fs):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, HOME).replace("\\", "/")
            seen.add(rel)
            body, st = body_and_stamp(load(p))
            if st is None:
                add("UNSTAMPED", rel)
                continue
            if "body" not in st or "src" not in st:
                add("BAD-STAMP", rel, "missing body= or src=")
                continue
            computed, recorded = sha(body), st["body"].replace("sha256:", "")
            local = computed != recorded
            moved = False
            if REPO:
                up = os.path.join(REPO, st["src"])
                if not os.path.isfile(up):
                    add("UPSTREAM-MISSING", rel, "src=" + st["src"])
                    continue
                moved = sha(body_and_stamp(load(up))[0]) != recorded
            add({(0, 0): "OK", (1, 0): "LOCAL", (0, 1): "STALE", (1, 1): "LOCAL+STALE"}[(local, moved)],
                rel, "v=" + st.get("v", "?"))

for name in ENTRY_NAMES:
    p = os.path.join(HOME, name)
    if not os.path.isfile(p):
        continue
    seen.add(name)
    st = entry_stamp(load(p))
    if st is None:
        add("UNSTAMPED", name)
    elif REPO and rv and st.get("v") != rv:
        add("STALE", name, "block v=%s repo v=%s" % (st.get("v"), rv))
    else:
        add("OK", name, "block v=" + st.get("v", "?"))

if REPO:
    for dp, _, fs in os.walk(REPO):
        for fn in sorted(fs):
            if not fn.endswith(".md"):
                continue
            _, st = body_and_stamp(load(os.path.join(dp, fn)))
            if not st or "src" not in st:
                continue
            rel = os.path.relpath(target(HOME, st["src"]), HOME).replace("\\", "/")
            if rel not in seen:
                add("MISSING", rel, "src=" + st["src"])

print("STATUS         FILE  NOTE")
for _, status, rel, note in sorted(rows):
    print(status.ljust(14) + rel + ("  " + note if note else ""))
print()
print("drift: %d of %d need attention" % (bad, len(rows)))
sys.exit(0 if bad == 0 else 1)
'@
$REPO = "$HOME\agentrule"   # 改成你 clone 的仓库路径
$code | python - "$HOME\.omp\agent" "$REPO"
exit $LASTEXITCODE   # 让脚本退出码 = 检测器退出码
```

不带第二个参数 = 只查本地完整性（`OK` / `LOCAL` / `UNSTAMPED`），查不出上游是否变旧。

三套 harness 的 `<home>`：omp `~/.omp/agent`、codex `~/.codex`、claude `~/.claude`。

### 2.2 样例输出

脏安装（上游已发新版，本地又改过一份、漏装一份、还留着一份无戳旧文件）：

```text
STATUS         FILE  NOTE
STALE         AGENTS.md  block v=2026.10.0 repo v=2026.11.0
STALE         AgentRule/protocol/01-dispatch.md  v=2026.10.0
UNSTAMPED     AgentRule/protocol/03-legacy.md
MISSING       AgentRule/protocol/04-recovery.md  src=protocol/04-recovery.md
LOCAL         AgentRule/protocol/02-local.md  v=2026.11.0
OK            AgentRule/protocol/00-floor.md  v=2026.11.0
OK            skills/verify/SKILL.md  v=2026.11.0

drift: 5 of 7 need attention
```

同一条命令，升级完之后：

```text
STATUS         FILE  NOTE
OK            AGENTS.md  block v=2026.11.0
OK            AgentRule/protocol/00-floor.md  v=2026.11.0
OK            AgentRule/protocol/01-dispatch.md  v=2026.11.0
OK            AgentRule/protocol/02-local.md  v=2026.11.0
OK            AgentRule/protocol/04-recovery.md  v=2026.11.0
OK            skills/verify/SKILL.md  v=2026.11.0

drift: 0 of 6 need attention
```

路径一律相对 `<home>` 打印，所以输出可以直接贴进 issue，不带本机绝对路径。

### 2.3 状态表

| 状态 | 判据 | 意思 | 默认动作 |
|---|---|---|---|
| `OK` | 三方一致 | 不用管 | 无 |
| `STALE` | 上游正文 ≠ 戳的 `body`，且本地没改 | 有新版本 | 覆盖（§4 的「可自动覆盖」清单） |
| `LOCAL` | 重算正文 ≠ 戳的 `body`，且上游没变 | 你改过 | 保留；或提回仓库；或接受长期红 |
| `LOCAL+STALE` | 两边都变 | 需要合并 | 三方合并（§3.1） |
| `MISSING` | 仓库有、本地没有 | 装漏了 | 补装（重跑安装器；无冲突时直接写入） |
| `UPSTREAM-MISSING` | 戳的 `src` 在仓库里找不到 | 上游改名或删除 | 先确认是哪种；改名按 `id` 追，删除则留档后移除 |
| `UNSTAMPED` | 没有戳 | 装的是盖戳前的版本 | 迁移（§6） |
| `VERSION-SPLIT` | 仓库内 `v` 不唯一 | 发布盖戳没盖全 | 先修仓库，别升级 |
| `BAD-STAMP` | 有戳但缺 `body=` 或 `src=` | 戳写坏了 | 重盖戳（§3.2） |

**退出码**：`0` 全部 `OK`；`1` 有需要处理的行；`2` 路径不对（不是目录）。

### 2.4 三种哈希记录，各答一半

| 记录 | 谁写 | 记了什么 | 能答 | 不能答 |
|---|---|---|---|---|
| `<target>/.agentrule-deploy/<run-id>/manifest.json` | 安装器每次真跑 | 每个文件的路径、`sha256`、`create`/`overwrite`、备份路径 | 这次装了什么、怎么卸 | 不带版本和上游路径；多次安装散成多个 run 目录 |
| 文件头的戳 | 发布侧 | 版本、正文哈希、来源路径 | 这份文件本身旧没旧、谁改的 | 不覆盖非 Markdown |
| `install/install.ps1 --verify`（= 安装器的字节级比对） | 现算 | 已装文件 ↔ **当前 checkout** | 装的和这个 checkout 是否逐字节一致 | checkout 本身旧了照样绿；分不清是上游改了还是你改了 |

正确用法是**先 `git pull`（或 checkout 目标 tag），再跑 §2 的对账，最后用 `install/install.ps1 --verify` 收口**。
顺序反了，`install.ps1 --verify` 只会告诉你「和旧 checkout 一致」。

---

## 3 · 判读之后做什么

### 3.1 三方合并（`LOCAL+STALE`）

base 从 tag 取，因为戳里的 `v` 就是当时的 tag：

```bash
git -C "$REPO" show "v2026.10.0:protocol/01-dispatch.md" > /tmp/base.md
git merge-file -p \
  "$HOME/.omp/agent/AgentRule/protocol/01-dispatch.md" \
  /tmp/base.md \
  "$REPO/protocol/01-dispatch.md" > /tmp/merged.md
```

`git merge-file` 退出码：`0` 无冲突、`1` 有冲突（`<<<<<<<` 标记）、`>1` 出错。

- 无冲突 → 覆盖，然后重盖戳（§3.2）。
- 有冲突 → 人工看。**别整份选一边**：先判断这段是「上游修的事故」还是「本地机器的路径/模型」，两边各自保留。

tag 不存在（老版本没打 tag）→ 没有 base，只能人工 `diff` 两个版本，按语义合。

### 3.2 重盖戳

合完、或决定保留本地改动之后，必须把戳更新成「当前正文 + 当前版本」，否则它会永远红，报告也就失去信号。

盖戳 = 删掉旧戳行，算新 `body`，写回一行。**本页只给算法，不提供自动改写脚本**——写不写、什么时候写由你决定：

```bash
python - "$HOME/.omp/agent/AgentRule/protocol/01-dispatch.md" 2026.11.0 <<'PY'
import sys
path, v = sys.argv[1], sys.argv[2]
lines = open(path, "rb").read().replace(b"\r\n", b"\n").split(b"\n")
i = next((k for k, l in enumerate(lines) if l.startswith(b"<!-- agentrule:")), None)
body = b"\n".join(lines[:i] + lines[i+1:]) if i is not None else b"\n".join(lines)
import hashlib
print("<!-- agentrule: v=%s id=<id> body=sha256:%s merge=replace src=<repo path> -->"
      % (v, hashlib.sha256(body).hexdigest()))
PY
```

它只**打印**新戳行，不写文件。确认后手工替换第一行。

---

## 4 · 三套 harness 的升级步骤

### 4.0 通用顺序

1. **备份**。`--force` 覆盖前自动备份到 `<target>/.backup-<时间戳>/`（`--target` 指向的根目录，通常是用户家目录）；手工 `cp` 前自己先留 `*.before-<日期>`。
2. **取新版**。`git -C "$REPO" pull --ff-only`，或 `git checkout v2026.11.0`。
3. **看计划**。`install.ps1 --dry-run`：只打印，不写。计划里只有四类：`CREATE` / `SAME` / `CONFLICT` / `ENTRY_*`。
4. **处理冲突**。安装器是**全有或全无**：只要有一个 `CONFLICT`，它打印清单后 exit 2，**一个文件都不写**。两条路：
   - **只补缺**：把清单里的冲突文件 `mv` 到备份目录，再重跑（安装器看到 `CREATE` 就会写）。
   - **确认全部可覆盖**：`--force`（覆盖前自动备份）。仅当 §2 报告里**没有** `LOCAL` / `LOCAL+STALE` 时才允许。
5. **跑安装**。写入后生成 `<target>/.agentrule-deploy/<run-id>/manifest.json`，记下每个文件的 sha256、动作和备份路径——卸载与回滚靠它，不靠记忆。
6. **验收**。`install/install.ps1 --verify`（字节级，`bad 0`）+ `install/verify.ps1 --harness <h> --target $HOME`（健康检查，`VERDICT: PASS`）+ §2 对账，三条都绿。
7. **重启 harness**。入口文件是启动时读的，不重启不生效。

**`--force` 的边界（最容易出事的一条）**：它覆盖**所有**冲突项，包括入口块，不分青红皂白。
只要报告里出现一条 `LOCAL` 或 `LOCAL+STALE`，就**不许整库 `--force`**；改成逐份 `cp` 可覆盖的那几份。
本机配置（模型、provider、MCP、权限、hook）永远不在 `--force` 的允许范围里。

### 4.1 omp（`~/.omp/agent`）

| 文件 | 归属 | `merge` | 升级动作 |
|---|---|---|---|
| `AgentRule/**` | 仓库 | `replace` | 可整份覆盖 |
| `skills/**` | 仓库 | `replace` | 可整份覆盖；本地改过的技能会丢，先看报告 |
| `AGENTS.md` 托管块 | 仓库 | `block` | 只换块，块外不动 |
| `RULES.md` | 本机 | `manual` | **手工**。每轮注入的硬地板，含本机路径与门清单；仓库不发行 |
| `config.yml`、`models.yml`、`mcp.json`、`settings.json` | 本机 | `manual` | **不覆盖**。模型、provider、MCP 注册、权限都在这里 |
| `hooks/pre/guards.ts` | 本机 | `manual` | **手工**。门是本地实现，覆盖等于把门删了 |
| `agents/*.md` | 本机 | `manual` | **手工**。角色提示词跟本机模型档位绑定 |

```powershell
powershell -NoProfile -File install/install.ps1 --harness omp --target $HOME --dry-run
# 有 CONFLICT：按 §2 对账，把可覆盖的冲突文件挪走再重跑；全部可覆盖时才 --force
powershell -NoProfile -File install/install.ps1 --harness omp --target $HOME
powershell -NoProfile -File install/verify.ps1 --harness omp --target $HOME
```

回滚：`cp -r "$HOME/.backup-<时间戳>/." "$HOME/"`。

### 4.2 codex（`~/.codex`）

| 文件 | 归属 | `merge` | 升级动作 |
|---|---|---|---|
| `AgentRule/**` | 仓库 | `replace` | 可整份覆盖 |
| `skills/**` | 仓库 | `replace` | 可整份覆盖。`skills/.system/` 是 codex 自带的，不在仓库清单里，**别动** |
| `AGENTS.md` 托管块 | 仓库 | `block` | 只换块 |
| `config.toml` | 本机 | `manual` | **不覆盖**。provider、API key 环境变量名、MCP、sandbox 策略都在这 |
| `*.config.toml`（profile） | 本机 | `manual` | **不覆盖** |
| `agents/*.toml` | 本机 | `manual` | **手工**。模型名与 reasoning effort 是本机选择 |

```powershell
powershell -NoProfile -File install/install.ps1 --harness codex --target $HOME --dry-run
powershell -NoProfile -File install/install.ps1 --harness codex --target $HOME
powershell -NoProfile -File install/verify.ps1 --harness codex --target $HOME
```

这套 codex 配置没有 hook：规则是 guidance，不拦人。升级只改行为，不改拦截能力——**别把「装上了」当成「有门了」**。

### 4.3 claude code（`~/.claude`）

| 文件 | 归属 | `merge` | 升级动作 |
|---|---|---|---|
| `AgentRule/**` | 仓库 | `replace` | 可整份覆盖 |
| `skills/**` | 仓库 | `replace` | 可整份覆盖。保持一种形态：要么指针、要么完整副本，别两份并存 |
| `CLAUDE.md` 托管块 | 仓库 | `block` | 只换块；文件不存在时安装器新建 |
| `settings.json` | 本机 | `manual` | **不覆盖**。permissions、model、plugins、statusLine |
| `plugins/` | 本机 | `manual` | **不动** |

```powershell
powershell -NoProfile -File install/install.ps1 --harness claude --target $HOME --dry-run
powershell -NoProfile -File install/install.ps1 --harness claude --target $HOME
powershell -NoProfile -File install/verify.ps1 --harness claude --target $HOME
```

claude 的入口只有 `CLAUDE.md`（没有 `AGENTS.md`）。如果 `~/.claude/skills/<name>/SKILL.md` 是指针（正文只写 canonical 路径），覆盖成完整副本会让同一份技能出现两个版本——**升级时保持原来的形态**。

---

## 5 · 发布侧：让戳存在

戳不是用户盖的，是**发布时**盖的。顺序：

1. 改完规则，跑发布步骤：给每个 `.md` 盖戳（`v`、`id`、`body`、`merge`、`src`）。
2. 检查全库 `v` 一致（不一致就是 `VERSION-SPLIT`）。
3. `git tag v2026.11.0`。
4. 发布。

盖戳只加/替换第一行注释，不动正文。发布前的 `git diff` 应该只有新增的戳行。
**幂等**：已有戳的文件重盖 = 替换旧戳行，不叠加。

`merge` 字段是给人（和 agent）看的标签，安装器不读它——`replace` / `manual` 的边界靠 §4 的流程执行，不靠脚本强制。

---

## 6 · 迁移：从没有戳到有戳

第一次升级时，旧文件全是 `UNSTAMPED`。逐份判断「正文是否真的不同」：

```bash
diff <(grep -v '^<!-- agentrule:' "$HOME/.omp/agent/AgentRule/protocol/00-floor.md") \
     <(grep -v '^<!-- agentrule:' "$REPO/protocol/00-floor.md")
```

- 无输出 = 正文一样，直接 `cp` 换成带戳版本。
- 有输出 = 你改过，按 §3.1 合并（base 用仓库上一版）。

顺序：先迁 `AgentRule/**` 和 `skills/**`（纯文档），再迁入口块（`--force` 只换块），最后才碰 §4 里标 `manual` 的本机文件。

注意：带戳版本比旧文件多一行，字节不同，所以安装器会把它们判成 `CONFLICT` 并整体拒绝写入——迁移必须手工 `cp`，不能指望安装器。

---

## 7 · 三个反例

| 做法 | 后果 | 正确做法 |
|---|---|---|
| 整库 `--force` | 本地改动、本机配置、hook 一起被冲掉 | 先看对账，只对 `STALE` 的 `replace` 文件逐份覆盖 |
| 只跑 `verify.ps1` | checkout 自己旧了照样绿 | 先 `git pull`，再对账，最后 `verify.ps1` |
| 改了文件不重盖戳 | `LOCAL` 永久红，报告失去信号 | 合并完立刻重盖戳（§3.2） |

---

## 8 · 这套机制不保证什么

- **不证明新规则更好**。哈希只回答「变没变」，不回答「该不该跟」。跟不跟是人的决定。
- **不管非 Markdown**。脚本、hook、配置没有戳；它们靠 `install/verify.ps1` 和人工 `diff`。
- **入口块只比版本**。块内被本地改过也报 `OK`——但升级会整块覆盖，所以本地改动必须放块外。
- **`LOCAL` 不会自己消失**。你接受本地改动，它就长期红；这是有意的，红名单就是待合并清单。
- **检测器只读**。它不修、不备份、不联网；所有写操作仍要人执行并留备份。
- **没有在真实仓库上跑过**。本页样例输出来自 6 个文件的沙箱（1 个 repo 目录 + 1 个 harness home），不是任何真实安装；真实仓库当前还没有戳，第一次盖戳前所有文件都会报 `UNSTAMPED`。

---

## 9 · 复现

本页样例的构造（三分钟）：

1. 建 `repo/protocol/` 与 `home/AgentRule/protocol/` 两个目录。
2. 按 §1.1 写 3 份带戳的文档；其中一份在 `home` 里换成旧正文 + 旧 `v`（造 `STALE`），一份装好后改一个字（造 `LOCAL`），一份不写戳（造 `UNSTAMPED`），再在 `repo` 里多放一份没装的（造 `MISSING`）。
3. 在 `home/AGENTS.md` 写一个带旧 `v` 的托管块（造入口 `STALE`）。
4. 跑 §2.1 的命令；然后把 `home` 里所有文件按 `repo` 覆盖一遍，再跑一次，应得 `drift: 0`、退出码 0。

负控：在干净副本里改任意一个词，重跑，应只多出一行 `LOCAL`，退出码 1。

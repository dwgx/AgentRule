#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check-protocol.py — 校验 protocol/manifest.tsv 与六页正文是否对得上。

manifest.tsv 是 protocol/ 的账本：每页一行，记 id、修订号、字节、行数、
依赖和一句话摘要。这个脚本把账本和正文对齐；红了只有两种可能——账本
过期，或正文改错了。

判据（原文，逐条）：
  1. 字节数 / 行数：manifest 的 `bytes` / `lines` 与文件一致。
  2. 行数预算：manifest 里的协议页合计 ≤ 400 行。
  3. `> EN:`：每页有一行以 `> EN:` 开头的英文 gloss，正文 ≤ 120 字符。
  4. 指纹：每页前 5 行内有 `<!-- source: ... -->`，内容非空。
  5. 链接：每页的相对链接（`../` 写法）都能解析到实际文件。
  6. 依赖：`depends_on` 里的 id 必须在本账本里，且不能依赖自己。
  7. 覆盖：`protocol/NN-*.md` 必须都在账本里，账本不能列不存在的页。

口径（换一种读法就改判的行，逐条写清）：
  * 「字节数」读成**检出时的原始字节** → Windows 的 CRLF 检出会多出每行 1 B，
    判定翻转。所以先 CRLF -> LF 再量：`.gitattributes` 规定 `*.md text eol=lf`，
    仓库里存的就是 LF 形态，检出差异不是内容差异。
  * 「协议页」读成 `protocol/` 下所有 `.md` → README 与 `*.en.md` 会进预算，
    判定翻转。所以预算只算 manifest 里的行（六页），README 与英文页不列账、
    不计预算；它们仍受链接与脱敏门约束。
  * 「行数」读成 `wc -l` 的输出 → 末行没换行时少算 1。这里按「有内容的最后
    一行也算一行」计，与 `scripts/budget.py` 同一口径。
  * 「`> EN:` 行」读成**任何**含 `EN:` 的行 → 正文里引用这个词也会命中。
    所以只认行首 `> EN:`（前面允许空白）。
  * 「指纹」读成文件任意位置 → 指纹被挪到页尾也能过。所以限定前 5 行。
  * 「链接可解析」读成含代码块里的示例 → 示例里的假路径会误报。所以先去掉
    围栏代码块与行内代码，再抽 `[文字](目标)`；`http(s)`、`mailto:`、纯锚点跳过。
  * 「version」读成 semver → 整数修订号被判错。这里只要求数字，允许 `1` 或 `1.2`。
  * 分母为 0：账本一行都没有、或一个相对链接都没抽到，直接判 FAIL——
    「检查了 0 个文件，全部通过」是最贵的谎话。

用法：
    python scripts/check-protocol.py
    python scripts/check-protocol.py --root <仓库根>

退出码：0 = 全过；1 = 有 FAIL（包括分母为 0）；2 = 找不到仓库根
"""

from __future__ import annotations

import argparse
import os
import re
import sys

MANIFEST_REL = os.path.join("protocol", "manifest.tsv")
HEADER = ["file", "id", "version", "bytes", "lines", "depends_on", "summary"]
GROUPS = ["manifest", "coverage", "bytes", "lines", "en", "source", "links", "deps", "budget"]

LINE_BUDGET = 400          # 协议页合计行数上限
EN_MAX_CHARS = 120         # `> EN:` 正文上限
SOURCE_WINDOW = 5          # 指纹必须出现在前 N 行

PAGE_RE = re.compile(r"^\d\d-[^/]+\.md$")
SOURCE_RE = re.compile(r"^<!--\s*source:\s*(\S.*?)\s*-->\s*$")
EN_RE = re.compile(r"^>\s*EN:\s*(.*)$")
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
SKIP_SCHEMES = ("http://", "https://", "mailto:", "#")


class Report:
    """按检查组计 PASS/FAIL；最后一行固定为 `[summary] PASS N  FAIL N`。"""

    def __init__(self) -> None:
        self.groups: dict[str, list[int]] = {g: [0, 0] for g in GROUPS}
        self.failures: list[str] = []
        self.notes: list[str] = []

    def ok(self, group: str) -> None:
        self.groups[group][0] += 1

    def bad(self, group: str, msg: str) -> None:
        self.groups[group][1] += 1
        self.failures.append(f"[{group}] {msg}")

    def note(self, msg: str) -> None:
        self.notes.append(msg)

    def emit(self) -> int:
        total_pass = total_fail = 0
        for group in GROUPS:
            p, f = self.groups[group]
            print(f"[{group}] PASS {p}  FAIL {f}")
            total_pass += p
            total_fail += f
        for msg in self.failures:
            print(f"  FAIL {msg}")
        for msg in self.notes:
            print(f"  note: {msg}")
        print(f"[summary] PASS {total_pass}  FAIL {total_fail}")
        return 0 if total_fail == 0 and total_pass > 0 else 1


def find_root(start: str) -> str:
    """向上找带 protocol/manifest.tsv 的目录。"""
    cur = os.path.abspath(start)
    for _ in range(8):
        if os.path.isfile(os.path.join(cur, MANIFEST_REL)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return ""


def to_repo_form(raw: bytes) -> bytes:
    """检出时的 CRLF 不算内容；仓库里存 LF（见 .gitattributes）。"""
    return raw.replace(b"\r\n", b"\n")


def count_lines(data: bytes) -> int:
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


def read_manifest(path: str) -> tuple[list[dict], list[str], bool]:
    """返回 (数据行, 问题列表, 表头是否正确)。"""
    with open(path, "rb") as fh:
        text = fh.read().decode("utf-8-sig")
    lines = text.splitlines()
    problems: list[str] = []

    header_at = next((i for i, line in enumerate(lines, 1) if line.strip()), None)
    if header_at is None:
        return [], ["manifest.tsv: file is empty"], False
    got = [c.strip() for c in lines[header_at - 1].split("\t")]
    if got != HEADER:
        return [], [f"manifest.tsv:{header_at}: header must be {'TAB'.join(HEADER)}"], False

    rows: list[dict] = []
    for i in range(header_at, len(lines)):
        line = lines[i]
        if not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) != len(HEADER):
            problems.append(
                f"manifest.tsv:{i + 1}: expected {len(HEADER)} columns, got {len(cols)}"
            )
            continue
        rows.append(dict(zip(HEADER, (c.strip() for c in cols))))
    return rows, problems, True


def parse_deps(value: str) -> list[str]:
    if value.strip() in ("", "-"):
        return []
    return [p.strip() for p in value.split(",") if p.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description="校验 protocol/manifest.tsv 与正文一致")
    ap.add_argument("--root", default="", help="仓库根（默认从当前目录向上找 protocol/manifest.tsv）")
    args = ap.parse_args()

    root = find_root(args.root or os.getcwd())
    if not root:
        print(f"找不到仓库根：向上没有 {MANIFEST_REL}", file=sys.stderr)
        return 2

    rows, problems, header_ok = read_manifest(os.path.join(root, MANIFEST_REL))
    rep = Report()

    # ---- 1. 账本本身 ----
    if header_ok:
        rep.ok("manifest")
    for msg in problems:
        rep.bad("manifest", msg)
    if not rows:
        rep.bad("manifest", "manifest.tsv: 没有数据行（分母为 0）")

    for row in rows:
        issues = []
        parts = row["file"].split("/")
        if len(parts) != 2 or parts[0] != "protocol" or ".." in parts or not parts[1]:
            issues.append("file 必须是 protocol/<名字>.md")
        if not row["id"]:
            issues.append("id 为空")
        if not re.fullmatch(r"\d+(\.\d+)*", row["version"]):
            issues.append(f"version {row['version']!r} 不是数字")
        if not re.fullmatch(r"\d+", row["bytes"]):
            issues.append(f"bytes {row['bytes']!r} 不是整数")
        if not re.fullmatch(r"\d+", row["lines"]):
            issues.append(f"lines {row['lines']!r} 不是整数")
        if not row["summary"]:
            issues.append("summary 为空")
        if issues:
            rep.bad("manifest", f"{row['file'] or '(空 file)'}: " + "; ".join(issues))
        else:
            rep.ok("manifest")

    ids = [r["id"] for r in rows]
    files = [r["file"] for r in rows]
    for label, seq in (("id", ids), ("file", files)):
        dupes = sorted({x for x in seq if seq.count(x) > 1})
        if dupes:
            rep.bad("manifest", f"重复的 {label}: {', '.join(dupes)}")
        else:
            rep.ok("manifest")

    # ---- 2. 覆盖：protocol/NN-*.md 必须在账本里，账本不能列不存在的页 ----
    proto_dir = os.path.join(root, "protocol")
    present: set[str] = set()
    if os.path.isdir(proto_dir):
        for name in os.listdir(proto_dir):
            if PAGE_RE.match(name) and not name.endswith(".en.md"):
                present.add("protocol/" + name)
    listed = set(files)
    if not present:
        rep.bad("coverage", "protocol/ 下没有 NN-*.md（分母为 0）")
    else:
        missing = sorted(present - listed)
        if missing:
            rep.bad("coverage", f"账本漏了: {', '.join(missing)}")
        else:
            rep.ok("coverage")
    extra = sorted(listed - present)
    if extra:
        rep.bad("coverage", f"账本列了不存在的页: {', '.join(extra)}")
    else:
        rep.ok("coverage")

    # ---- 3. 逐页：字节 / 行数 / EN / 指纹 / 链接 ----
    measured: list[tuple[str, int]] = []
    total_links = 0

    for row in rows:
        rel = row["file"]
        abs_path = os.path.join(root, *rel.split("/"))
        if not os.path.isfile(abs_path):
            for group in ("bytes", "lines", "en", "source", "links"):
                rep.bad(group, f"{rel}: 文件不存在")
            continue

        with open(abs_path, "rb") as fh:
            raw = fh.read()
        data = to_repo_form(raw)
        if len(raw) != len(data):
            rep.note(f"{rel}: CRLF 归一化 {len(raw)} -> {len(data)} B")

        size = len(data)
        nlines = count_lines(data)
        measured.append((rel, nlines))

        if str(size) == row["bytes"]:
            rep.ok("bytes")
        else:
            rep.bad("bytes", f"{rel}: 盘上 {size} B，账本 {row['bytes']} B")

        if str(nlines) == row["lines"]:
            rep.ok("lines")
        else:
            rep.bad("lines", f"{rel}: 盘上 {nlines} 行，账本 {row['lines']} 行")

        text = data.decode("utf-8", errors="replace")
        lines = text.splitlines()

        en_hits = []
        for i, line in enumerate(lines, 1):
            m = EN_RE.match(line.strip())
            if m:
                en_hits.append((i, m.group(1).strip()))
        if not en_hits:
            rep.bad("en", f"{rel}: 没有 '> EN:' 行")
        else:
            i, value = en_hits[0]
            if not value:
                rep.bad("en", f"{rel}:{i}: '> EN:' 后面是空的")
            elif len(value) > EN_MAX_CHARS:
                rep.bad("en", f"{rel}:{i}: EN gloss {len(value)} 字符 > {EN_MAX_CHARS}")
            else:
                rep.ok("en")

        src = None
        for i, line in enumerate(lines[:SOURCE_WINDOW], 1):
            m = SOURCE_RE.match(line.strip())
            if m:
                src = (i, m.group(1).strip())
                break
        if not src:
            rep.bad("source", f"{rel}: 前 {SOURCE_WINDOW} 行没有 '<!-- source: ... -->'")
        elif not src[1]:
            rep.bad("source", f"{rel}:{src[0]}: 指纹内容为空")
        else:
            rep.ok("source")

        body = re.sub(r"```.*?```", "", text, flags=re.S)
        body = re.sub(r"`[^`\n]*`", "", body)
        here = 0
        broken: list[str] = []
        for m in LINK_RE.finditer(body):
            url = m.group(1).strip()
            if url.startswith("<") and url.endswith(">"):
                url = url[1:-1].strip()
            url = re.sub(r'\s+"[^"]*"$', "", url).split("#")[0].strip()
            if not url or url.startswith(SKIP_SCHEMES):
                continue
            here += 1
            target = os.path.normpath(os.path.join(os.path.dirname(abs_path), url))
            if not os.path.exists(target):
                broken.append(url)
        total_links += here
        if broken:
            rep.bad("links", f"{rel}: 死链 -> {', '.join(broken)}")
        else:
            rep.ok("links")

    if total_links == 0:
        rep.bad("links", "一个相对链接都没抽到（分母为 0）")
    else:
        rep.ok("links")

    # ---- 4. depends_on：id 必须存在，不能自依赖 ----
    known = set(ids)
    for row in rows:
        deps = parse_deps(row["depends_on"])
        issues = []
        for dep in deps:
            if dep == row["id"]:
                issues.append(f"{dep} 依赖自己")
            elif dep not in known:
                issues.append(f"未知 id {dep!r}")
        if len(deps) != len(set(deps)):
            issues.append("depends_on 有重复项")
        if issues:
            rep.bad("deps", f"{row['file']}: " + "; ".join(issues))
        else:
            rep.ok("deps")

    # ---- 5. 行数预算 ----
    total_lines = sum(n for _, n in measured)
    rep.note(f"协议页 {len(measured)} 篇 / {total_lines} 行（上限 {LINE_BUDGET}）")
    if not measured:
        rep.bad("budget", "一篇都没量到（分母为 0）")
    elif total_lines > LINE_BUDGET:
        rep.bad("budget", f"{total_lines} 行 > 上限 {LINE_BUDGET}")
    else:
        rep.ok("budget")

    return rep.emit()


if __name__ == "__main__":
    sys.exit(main())

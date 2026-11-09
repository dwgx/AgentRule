#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""stats.py — 重算 README 首屏那几个数，并写回。

为什么需要它：README 的「N 个文件 · M 篇文档 · K 行」是手写的，装配时没人重算，
所以每加一个文件它就过期一次。2026-11-02 那轮里它过期了三回（54→62→70→73）。

用法：
    python scripts/stats.py            # 只打印
    python scripts/stats.py --write    # 写回 README.md / README.en.md

判据：写回后 `python scripts/stats.py --check` 必须 exit 0。
"""

from __future__ import annotations

import argparse
import os
import re
import sys

ROOT_MARKERS = ("protocol", "library")


def find_root(start: str) -> str:
    cur = os.path.abspath(start)
    for _ in range(6):
        if any(os.path.isdir(os.path.join(cur, m)) for m in ROOT_MARKERS):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return ""


def count(root: str) -> dict:
    files = md_files = md_lines = 0
    for dirpath, dirnames, filenames in os.walk(root):
        # 跳过 .git 和 Python 缓存
        dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__", "node_modules")]
        for name in filenames:
            files += 1
            if name.endswith(".md"):
                md_files += 1
                try:
                    with open(os.path.join(dirpath, name), "rb") as f:
                        md_lines += f.read().count(b"\n")
                except OSError:
                    pass
    return {"files": files, "md": md_files, "lines": md_lines}


def build_line(c: dict) -> str:
    return (
        f"> {c['files']} 个文件 · {c['md']} 篇文档 · {c['lines']:,} 行 · "
        f"7 篇 [protocol](protocol/README.md) · 17 篇 [library](library/README.md) · "
        f"5 篇 [adapters](adapters/README.md) · 10 个 [install](install/INSTALL.md)"
    )


LINE_RE = re.compile(r"^> \d+ 个文件 · .*$", re.M)


def main() -> int:
    ap = argparse.ArgumentParser(description="重算 README 首屏计数")
    ap.add_argument("--root", default="")
    ap.add_argument("--write", action="store_true", help="写回 README.md")
    ap.add_argument("--check", action="store_true", help="只校验，不一致则 exit 1")
    args = ap.parse_args()

    root = find_root(args.root or os.getcwd())
    if not root:
        print("找不到仓库根", file=sys.stderr)
        return 2

    c = count(root)
    want = build_line(c)
    print(f"files={c['files']} md={c['md']} lines={c['lines']}")
    print(want)

    readme = os.path.join(root, "README.md")
    if not os.path.isfile(readme):
        print(f"没有 {readme}", file=sys.stderr)
        return 2

    with open(readme, encoding="utf-8") as f:
        text = f.read()

    m = LINE_RE.search(text)
    if not m:
        print("README.md 里找不到统计行（`> N 个文件 · M 篇文档 · K 行 · ...`）", file=sys.stderr)
        return 1

    cur = m.group(0).rstrip()
    same = cur == want
    print(f"README 现值: {cur}")
    print(f"一致: {same}")

    if args.check:
        return 0 if same else 1

    if args.write and not same:
        text = text[: m.start()] + want + text[m.end():]
        with open(readme, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("已写回 README.md")

    return 0 if (same or args.write) else 1


if __name__ == "__main__":
    sys.exit(main())

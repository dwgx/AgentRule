#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen-scope.py — 生成并校验 install/scope.txt：安装器唯一承认的源文件清单。

为什么需要它：安装器原来「递归枚举整棵树，只排除 .git / node_modules」，于是本地
未跟踪或被忽略的私人文件（笔记、草稿、.env、会话导出）也会被复制进
`<harness>/AgentRule/`。改法是把「装什么」从**运行时排除**改成**发布时声明**：
清单外的文件安装器连读都不读。清单本身必须能被重算和比对，否则它自己就会漂移，
所以有本脚本。

判据（原文，逐条）：
  1. 清单 = 发布树里除 `.git` / `node_modules` / `__pycache__` / `.backup-*` 之外的全部文件。
  2. 一行一个相对路径，`/` 分隔，LF 结尾，按 LC_ALL=C 字节序排序。
  3. `--check`：清单与磁盘逐条一致（条数、内容、顺序都算），不一致 exit 1。
  4. 清单里不许有绝对路径、`..`、反斜杠、目录条目；清单自身也在清单里。

口径（换一种读法就改判的行，逐条写清）：
  * 「发布树根」读成「当前目录或 git 根」→ 从 `ops/oss/` 跑就会把 500 多个非发布
    文件列进来。所以按 `protocol/` + `library/` 两个标记目录定位根（与
    `scripts/stats.py`、安装器的 `Find-SourceRoot` 同一判据）。
  * 「排序」读成 Python 默认字符串序 → 非 ASCII 名字与 `LC_ALL=C sort` 不同序，
    同一份清单在两台机器上 `--check` 一个绿一个红。所以按 UTF-8 字节排序。
  * 「全部文件」读成含 `__pycache__` → 本机跑一次 `gates/run.py` 就多出 `.pyc`，
    清单每次抖动。构建产物与备份目录本来也不该发布，所以排除。
  * 「一致」读成集合相等 → 顺序变了也判绿，安装器的输出顺序就会在两台机器上
    不同，`--verify` 的逐行输出无法比对。所以顺序也算。
  * 分母为 0：清单为空直接 exit 1 —— 空清单会让安装器「成功装了 0 个文件」。

用法：
    python scripts/gen-scope.py            # 打印现状与判定，不写
    python scripts/gen-scope.py --write    # 重写 install/scope.txt
    python scripts/gen-scope.py --check    # 只校验（assemble.sh 与 CI 用这条）

退出码：0 = 一致；1 = 不一致 / 空清单；2 = 找不到发布树根
"""

from __future__ import annotations

import argparse
import os
import sys

sys.dont_write_bytecode = True

SCOPE_REL = "install/scope.txt"
ROOT_MARKERS = ("protocol", "library")
SKIP_DIRS = {".git", "node_modules", "__pycache__"}
SKIP_DIR_PREFIXES = (".backup-",)
SKIP_FILES = {".DS_Store", "Thumbs.db", "desktop.ini"}

HEADER = [
    "# AgentRule 安装范围清单 —— 安装器只复制这里列出的文件。",
    "#",
    "# 不在清单里的文件（本地笔记、未跟踪草稿、.env、日志、临时产物）安装器一律不读、不复制。",
    "# 这是 allowlist：清单缺失 / 为空 / 条目指向不存在的文件时，安装器退 4，",
    "# 不退回「整棵树都装」的旧行为 —— 静默装多了比装不起来更贵。",
    "#",
    "# 生成: python scripts/gen-scope.py --write",
    "# 校验: python scripts/gen-scope.py --check   （assemble.sh 与 CI 都跑这一条）",
    "# 格式: 一行一个相对路径，'/' 分隔，相对发布树根；# 开头是注释；空行忽略。",
]


def find_root(start: str) -> str:
    cur = os.path.abspath(start)
    for _ in range(6):
        if all(os.path.isdir(os.path.join(cur, m)) for m in ROOT_MARKERS):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return ""


def scan(root: str) -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_DIRS and not d.startswith(SKIP_DIR_PREFIXES)
        ]
        for name in filenames:
            if name in SKIP_FILES:
                continue
            full = os.path.join(dirpath, name)
            out.append(os.path.relpath(full, root).replace(os.sep, "/"))
    out.sort(key=lambda s: s.encode("utf-8"))
    return out


def render(files: list[str]) -> str:
    return "\n".join(HEADER + files) + "\n"


def read_manifest(path: str) -> list[str]:
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    return [ln.strip() for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]


def diff_lines(have: list[str], want: list[str]) -> list[str]:
    out = []
    have_set, want_set = set(have), set(want)
    missing = [p for p in want if p not in have_set]
    extra = [p for p in have if p not in want_set]
    if missing:
        out.append(f"清单缺 {len(missing)} 条（磁盘上有，清单里没有）:")
        out += [f"  - {p}" for p in missing[:10]]
        if len(missing) > 10:
            out.append(f"  … 还有 {len(missing) - 10} 条")
    if extra:
        out.append(f"清单多 {len(extra)} 条（清单里有，磁盘上没有）:")
        out += [f"  + {p}" for p in extra[:10]]
        if len(extra) > 10:
            out.append(f"  … 还有 {len(extra) - 10} 条")
    if not missing and not extra and have != want:
        first = next(i for i, (a, b) in enumerate(zip(have, want)) if a != b)
        out.append(f"顺序不一致：第 {first + 1} 行 清单={have[first]!r} 磁盘={want[first]!r}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 / 校验 install/scope.txt")
    ap.add_argument("--root", default="")
    ap.add_argument("--write", action="store_true", help="重写 install/scope.txt")
    ap.add_argument("--check", action="store_true", help="只校验，不一致 exit 1")
    args = ap.parse_args()

    root = find_root(args.root or os.getcwd())
    if not root:
        print(f"找不到发布树根（要同时有 {' + '.join(ROOT_MARKERS)} 两个目录）", file=sys.stderr)
        return 2

    want = scan(root)
    if not want:
        print(f"发布树里一个文件都没有: {root}", file=sys.stderr)
        return 1

    scope_path = os.path.join(root, *SCOPE_REL.split("/"))
    have = read_manifest(scope_path)
    same = have == want

    print(f"root={root}")
    print(f"manifest={SCOPE_REL}")
    print(f"disk={len(want)}  manifest={len(have)}  一致={same}")

    if args.write:
        text = render(want)
        old = ""
        if os.path.isfile(scope_path):
            with open(scope_path, encoding="utf-8") as f:
                old = f.read()
        if old == text:
            print("清单未变化，没有写盘")
        else:
            with open(scope_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"已写回 {SCOPE_REL}（{len(want)} 条）")
        return 0

    if same:
        print("OK: 清单与发布树一致")
        return 0

    for line in diff_lines(have, want):
        print(line)
    if args.check:
        print(f"FAIL: 跑 `python scripts/gen-scope.py --write` 重算，并 review 新增/删除的条目")
        return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())

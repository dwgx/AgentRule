#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""budget.py — 量这套规则书塞进 agent 上下文要花多少字节。

为什么需要它：`AGENTS.md` 在 Codex 里有**静默截断**，默认上限 32,768 B。
超了不报错，尾部直接消失。所以「文件存在」和「模型看到了」是两件事。

这个脚本回答三个问题：
  1. 每个入口/规则页多少字节、多少行？
  2. 全量塞进一个文件，会不会超 Codex 的上限？
  3. 超了的话，哪些页可以先不塞？

用法：
    python scripts/budget.py                 # 全部
    python scripts/budget.py --limit 32768   # 换一个上限
    python scripts/budget.py --json          # 机器可读

退出码：0 = 全部在限内；1 = 有组合超限；2 = 仓库根找错
"""

from __future__ import annotations

import argparse
import json
import os
import sys

# Codex 的默认上限（`project_doc_max_bytes`）。实测：40,000 B 的文件只进去 32,768 B，
# 尾部 marker 消失且无任何提示。设 65,536 才全文进入。
DEFAULT_LIMIT = 32768

# 「一次全塞」的候选集合。入口 = 每次会话都要读的；协议页 = 声明了「必须遵守」的。
# 协议页清单只从 protocol/manifest.tsv 读，别在这里再抄一份文件名。
ENTRY = ["AGENTS.md", "RULES.md"]
MANIFEST = os.path.join("protocol", "manifest.tsv")


def read_protocol_list(root: str) -> list[str]:
    """读 manifest.tsv 的 file 列（第一行是表头）。

    账本坏了就抛 ValueError，不静默跳过——少算一页的预算比算错更危险。
    """
    with open(os.path.join(root, MANIFEST), "rb") as fh:
        text = fh.read().decode("utf-8-sig")
    files: list[str] = []
    header_seen = False
    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        cols = [c.strip() for c in line.split("\t")]
        if not header_seen:
            if cols[0] != "file":
                raise ValueError(f"manifest.tsv:{i}: 第一列必须是 file")
            header_seen = True
            continue
        if len(cols) != 7:
            raise ValueError(f"manifest.tsv:{i}: 需要 7 列，得到 {len(cols)} 列")
        if cols[0]:
            files.append(cols[0])
    return files


def find_root(start: str) -> str:
    """向上找带 protocol/ 或 library/ 的目录。"""
    cur = os.path.abspath(start)
    for _ in range(6):
        if os.path.isdir(os.path.join(cur, "protocol")) or os.path.isdir(
            os.path.join(cur, "library")
        ):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return ""


def measure(root: str, rel: str) -> dict:
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return {"path": rel, "exists": False, "bytes": 0, "lines": 0}
    with open(p, "rb") as f:
        raw = f.read()
    # 行数按 \n 计；CRLF 不会多算
    return {
        "path": rel,
        "exists": True,
        "bytes": len(raw),
        "lines": raw.count(b"\n") + (0 if raw.endswith(b"\n") or not raw else 1),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="量规则书的上下文预算")
    ap.add_argument("--root", default="", help="仓库根（默认自动向上找）")
    ap.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="截断上限，默认 32768")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()

    root = find_root(args.root or os.getcwd())
    if not root:
        print("找不到仓库根（向上 6 层都没有 protocol/ 或 library/）", file=sys.stderr)
        return 2

    try:
        proto = read_protocol_list(root)
    except (OSError, ValueError) as exc:
        print(f"读不了协议清单：{exc}", file=sys.stderr)
        return 2
    if not proto:
        print(f"{MANIFEST} 里没有协议页", file=sys.stderr)
        return 2

    entry_rows = [measure(root, p) for p in ENTRY]
    proto_rows = [measure(root, p) for p in proto]
    rows = entry_rows + proto_rows

    # 英文页是「替代品」不是「增量」：读中文版的人通常不会同时读英文版。
    # 但 protocol/ 里确实有这些文件 —— 谁把整个目录塞进去就会超。两个场景都报。
    en_dir = os.path.join(root, "protocol")
    en_rows = []
    if os.path.isdir(en_dir):
        for name in sorted(os.listdir(en_dir)):
            if name.endswith(".en.md"):
                en_rows.append(measure(root, "protocol/" + name))
    en_bytes = sum(r["bytes"] for r in en_rows)

    entry_bytes = sum(r["bytes"] for r in entry_rows)
    proto_bytes = sum(r["bytes"] for r in proto_rows)
    all_bytes = entry_bytes + proto_bytes

    over = all_bytes > args.limit

    if args.json:
        print(
            json.dumps(
                {
                    "root": root,
                    "limit": args.limit,
                    "entry_bytes": entry_bytes,
                    "protocol_bytes": proto_bytes,
                    "total_bytes": all_bytes,
                    "over_limit": over,
                    "headroom": args.limit - all_bytes,
                    "rows": rows,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 1 if over else 0

    print(f"仓库根 : {root}")
    print(f"上限   : {args.limit:,} B（Codex 默认 project_doc_max_bytes）")
    print()

    def table(title: str, rs: list[dict]) -> int:
        print(title)
        print(f"  {'字节':>8}  {'行':>5}  {'占比':>6}  路径")
        sub = 0
        for r in rs:
            if not r["exists"]:
                print(f"  {'—':>8}  {'—':>5}  {'—':>6}  {r['path']}  (不存在)")
                continue
            sub += r["bytes"]
            pct = (r["bytes"] / args.limit * 100) if args.limit else 0
            print(f"  {r['bytes']:>8,}  {r['lines']:>5}  {pct:>5.1f}%  {r['path']}")
        print()
        return sub

    table("入口（每次会话都读）", entry_rows)
    table("协议（声明「必须遵守」）", proto_rows)

    print(f"合计   : {all_bytes:,} B / {args.limit:,} B  ({all_bytes / args.limit * 100:.1f}%)")
    if en_rows:
        both = all_bytes + en_bytes
        print(
            f"中英都装: {both:,} B / {args.limit:,} B  ({both / args.limit * 100:.1f}%)"
            f"   ← 英文页 {len(en_rows)} 个，{en_bytes:,} B"
        )
        if both > args.limit and not over:
            print("        ↑ 超了。别把 protocol/ 整个目录塞进 AGENTS.md —— 中英各留一份。")
    if over:
        print(f"余量   : 超了 {all_bytes - args.limit:,} B")
        print()
        print("超限。三种处理：")
        print("  1. 入口只放指针，规则留在分篇按需读（推荐）")
        print("  2. 把上限提到 65,536（Codex: project_doc_max_bytes = 65536）")
        print("  3. 从上面表里挑最大的几页不塞进入口")
        # 给一个具体建议：按字节降序，砍到限内
        cand = sorted([r for r in proto_rows if r["exists"]], key=lambda r: -r["bytes"])
        need = all_bytes - args.limit
        cut, freed = [], 0
        for r in cand:
            if freed >= need:
                break
            cut.append(r["path"])
            freed += r["bytes"]
        if cut:
            print()
            print(f"  按字节降序，不塞这 {len(cut)} 页可省 {freed:,} B：")
            for c in cut:
                print(f"    - {c}")
    else:
        print(f"余量   : {args.limit - all_bytes:,} B")
        print("在限内。但注意：**这只算字节，不算模型有没有读进去**。")

    print()
    print("口径：字节是文件原始大小（UTF-8）；中文 1 字 = 3 B。")
    print("这个脚本不证明：模型真的读到了、读到了真的遵守。")

    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())

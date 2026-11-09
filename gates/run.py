#!/usr/bin/env python3
"""跑夹具集：逐条喂给 reference.py，逐条对 expect。

用法：
    python gates/run.py                 # 正常跑；全对 exit 0
    python gates/run.py --mutate        # 默认把 recursive-delete 判据改坏
    python gates/run.py --mutate=all    # 三道门依次改坏
    python gates/run.py --verbose       # PASS 行也打 why

退出码：
    0  全部匹配，且没有变异
    1  有不匹配（正常跑 = 夹具抓到实现 bug；变异跑 = 变异被抓到，符合预期）
    2  用法错 / 夹具文件格式错
    3  变异跑却 0 条 FAIL —— 夹具集没抓到变异，这套夹具是废的
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# 不写 __pycache__：assemble.sh 用 find 数文件，.pyc 会被算进仓库。
sys.dont_write_bytecode = True

import reference  # noqa: E402  （必须在 dont_write_bytecode 之后）

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures.tsv"
COLUMNS = ("id", "gate", "expect", "payload", "why")
EXPECTS = {"ALLOW", "DENY"}

MUTATIONS = {
    "recursive-delete": (
        "is_under_temp() 恒真：所有删除目标都当成在 temp 里",
        lambda: setattr(reference, "is_under_temp", lambda path: True),
    ),
    "unexpanded-temp-var": (
        "TEMP_VAR 只剩 %TEMP%：%TMP% / %TMPDIR% 漏掉",
        lambda: setattr(reference, "TEMP_VAR", re.compile(r"%(TEMP)%", re.I)),
    ),
    "ai-attribution": (
        "BANNER 关闭：只剩 trailer 能抓",
        lambda: setattr(reference, "BANNER", re.compile(r"(?!x)x")),
    ),
}


class FixtureError(Exception):
    pass


def load_fixtures(path: Path) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != len(COLUMNS):
            raise FixtureError(f"{path.name}:{lineno}: 要 {len(COLUMNS)} 列，拿到 {len(parts)} 列")
        row = dict(zip(COLUMNS, parts))
        if row["id"] in seen:
            raise FixtureError(f"{path.name}:{lineno}: id 重复: {row['id']}")
        seen.add(row["id"])
        if row["expect"] not in EXPECTS:
            raise FixtureError(f"{path.name}:{lineno}: expect 只能是 ALLOW / DENY")
        if row["gate"] not in reference.GATES:
            raise FixtureError(
                f"{path.name}:{lineno}: 没有这道门的参考实现: {row['gate']}"
            )
        rows.append(row)
    return rows


def build_call(gate: str, payload: str) -> dict:
    if gate == "recursive-delete":
        return {"kind": "shell", "command": payload}
    if gate == "unexpanded-temp-var":
        return {"kind": "write", "path": payload}
    if gate == "ai-attribution":
        return {"kind": "commit", "message": payload.replace("<NL>", "\n")}
    raise FixtureError(f"payload 的写法没定义: {gate}")


def run(rows: list[dict], verbose: bool) -> int:
    matched = 0
    for row in rows:
        decision = reference.judge(row["gate"], build_call(row["gate"], row["payload"]))
        got = "ALLOW" if decision.allow else "DENY"
        ok = got == row["expect"]
        matched += ok
        status = "PASS" if ok else "FAIL"
        line = (
            f"{status}  {row['id']:<6}  {row['gate']:<19}"
            f"  expect={row['expect']:<5}  got={got:<5}"
        )
        if not ok:
            line += f"  rule={decision.rule or '-'}  span={decision.span or '-'}"
        if not ok or verbose:
            line += f"  why={row['why']}"
        print(line)
    print(f"[summary] match {matched}/{len(rows)}")
    return matched


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=True, description="跑门夹具集")
    parser.add_argument(
        "--mutate", nargs="?", const="recursive-delete", default=None,
        choices=sorted(MUTATIONS) + ["all"],
        help="故意把某道门的判据改坏，验证夹具集能抓到",
    )
    parser.add_argument("--verbose", action="store_true", help="PASS 行也打 why")
    args = parser.parse_args(argv)

    try:
        rows = load_fixtures(FIXTURES)
    except FixtureError as exc:
        print(f"[fixtures] {exc}", file=sys.stderr)
        return 2

    gates = sorted({row["gate"] for row in rows})
    print(f"[fixtures] {len(rows)} rows / {len(gates)} gates: {', '.join(gates)}")

    names = list(MUTATIONS) if args.mutate == "all" else (
        [args.mutate] if args.mutate else []
    )
    for name in names:
        description, apply = MUTATIONS[name]
        apply()
        print(f"[mutate] {name}: {description}")

    matched = run(rows, args.verbose)
    total = len(rows)

    if not names:
        if matched == total:
            print("[verdict] 夹具与判据一致 (exit 0)")
            return 0
        print(f"[verdict] {total - matched} 条不匹配 (exit 1)")
        return 1

    if matched == total:
        print("[verdict] 变异未被抓到：这套夹具证明不了任何事 (exit 3)")
        return 3
    print(f"[verdict] 变异被抓到：{total - matched} 条 FAIL (exit 1)")
    return 1


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
    except OSError as exc:  # Windows: 下游 `head` 关管道后 write 抛 OSError 22
        if getattr(exc, "errno", None) != 22:
            raise
        sys.exit(0)

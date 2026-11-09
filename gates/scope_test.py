#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scope_test.py — 证明安装器只装 `install/scope.txt` 里列出的文件。

为什么需要它：安装器原来「递归枚举整棵树，只排除 .git / node_modules」，本地未跟踪的
私人文件会跟着进 `<harness>/AgentRule/`。改法是把「装什么」改成发布时声明的清单。
这个测试把「清单外的东西装不进去」变成一条能红的判据：造一份发布树副本，往里塞
私人文件（根上、合法目录里、`.env`、会话导出、`.git` 里各一个），跑真安装器，然后
**逐文件比对目标目录与清单**。

判据（原文，逐条）：
  1. 跑完安装器，目标 `AgentRule/` 里的文件集合 **等于** 源 `install/scope.txt` 的条目集合。
  2. 私人文件一个都不在目标里（按名字与内容两路查）。
  3. 清单缺失 / 为空 / 有条目非法（`..`）/ 条目指向不存在的文件 → 安装器退 4，且**一个文件都不写**。
  4. 两个安装器（install.sh / install.ps1）跑出同一份文件集合。

口径（换一种读法就改判的行，逐条写清）：
  * 「等于清单」读成「清单里的都在」→ 多装的文件不会让判据红，而多装正是这个 bug 的
    形态。所以两个方向都比：缺一个 FAIL，多一个 FAIL。
  * 「私人文件不在」读成只查文件名 → 改名的私有内容查不到。所以再查一次内容：
    每个私人文件里放一个唯一串，目标里任何文件包含它都算 FAIL。
  * 「退 4」读成「非 0」→ 用法错误（1）也算通过。所以只认退出码 4（前置条件缺失）。
  * 「一个文件都不写」读成「AgentRule/ 不存在」→ 入口文件 `AGENTS.md` 可能被写。
    所以连入口一起查：目标里除预置的 harness 目录外，不许出现任何新文件。
  * 分母为 0：清单读出来是 0 条直接 FAIL —— 「装了 0 个文件，全部通过」是最贵的谎话。
  * 没装 powershell 的机器上 install.ps1 那条 SKIP，不假装通过；SKIP 会让退出码是 2。

用法：
    python gates/scope_test.py
    python gates/scope_test.py --keep      # 保留临时目录（失败时自动保留）

退出码：0 = 全 PASS；1 = 有 FAIL；2 = 没有 FAIL，但有 SKIP
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SCOPE_REL = Path("install") / "scope.txt"
SKIP_DIRS = {".git", "__pycache__", "node_modules"}

def mk(*parts: str) -> str:
    """运行期拼出唯一串：本文件里不出现完整标记，否则内容扫描会扫到自己。"""
    return "-".join(parts)


PRIVATE = {
    "secret.txt": mk("PRIVATE", "ROOT", "8f2a1c"),
    "library/private-notes.md": mk("PRIVATE", "LIBRARY", "4d9e77"),
    ".env.local": mk("PRIVATE", "ENV", "1b6c03"),
    "docs/session-export.jsonl": mk("PRIVATE", "SESSION", "9a55e1"),
    ".git/inside-git.txt": mk("PRIVATE", "GIT", "77c2d0"),
}
FORBIDDEN_NAMES = ("secret.txt", "private-notes.md", ".env.local", "session-export.jsonl", "inside-git.txt")

RESULTS: list[tuple[str, str, str]] = []  # (status, case, detail)


def record(status: str, case: str, detail: str = "") -> None:
    RESULTS.append((status, case, detail))
    line = f"{status:<4} {case}"
    if detail:
        line += f"   {detail}"
    print(line)


def run(cmd: list[str], cwd: Path) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True, timeout=240,
            stdin=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return 127, ""
    except subprocess.TimeoutExpired:
        return 124, "timeout"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def find_bash() -> str:
    for cand in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
        "/bin/bash",
        "/usr/bin/bash",
    ):
        if Path(cand).exists():
            return cand
    return shutil.which("bash") or ""


def find_powershell() -> str:
    for cand in ("powershell", "pwsh"):
        p = shutil.which(cand)
        if p:
            return p
    return ""


def copy_tree(src: Path, dst: Path) -> None:
    def ignore(dirpath: str, names: list[str]) -> set[str]:
        return {n for n in names if n in SKIP_DIRS or n.endswith(".pyc")}

    shutil.copytree(src, dst, ignore=ignore)


def read_scope(root: Path) -> list[str]:
    path = root / SCOPE_REL
    if not path.is_file():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        out.append(t)
    return out


def walk_rel(root: Path) -> set[str]:
    if not root.is_dir():
        return set()
    out = set()
    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            full = Path(dirpath) / name
            out.add(full.relative_to(root).as_posix())
    return out


def snapshot(root: Path) -> set[str]:
    """目标目录里所有文件（相对路径）—— 用来证明失败路径下什么都没写。"""
    return walk_rel(root)


def make_source(tmp: Path) -> Path:
    src = tmp / "src"
    copy_tree(ROOT, src)
    for rel, marker in PRIVATE.items():
        p = src / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(marker + "\n", encoding="utf-8")
    return src


def installed_docs(dst: Path) -> Path:
    return dst / ".omp" / "agent" / "AgentRule"


def check_install(kind: str, cmd: list[str], src: Path, dst: Path) -> None:
    before = snapshot(dst)
    rc, out = run(cmd, ROOT)
    if rc != 0:
        record("FAIL", f"{kind}: 安装退出码", f"rc={rc}（期望 0）")
        print(indent(out, 12))
        return
    record("PASS", f"{kind}: 安装退出码", "rc=0")

    want = set(read_scope(src))
    if not want:
        record("FAIL", f"{kind}: 清单非空", "读到 0 条")
        return

    got = walk_rel(installed_docs(dst))
    missing = sorted(want - got)
    extra = sorted(got - want)
    if missing:
        record("FAIL", f"{kind}: 清单里的文件都装了", f"缺 {len(missing)}: {missing[:3]}")
    else:
        record("PASS", f"{kind}: 清单里的文件都装了", f"{len(want)}/{len(want)}")
    if extra:
        record("FAIL", f"{kind}: 多装的文件", f"{len(extra)}: {extra[:5]}")
    else:
        record("PASS", f"{kind}: 多装的文件", "0 个")

    # 名字路：私人文件名一个都不许出现
    bad_names = [p for p in got if any(p.endswith(n) or f"/{n}/" in f"/{p}/" for n in FORBIDDEN_NAMES)]
    if bad_names:
        record("FAIL", f"{kind}: 私人文件名不在目标里", f"{bad_names[:3]}")
    else:
        record("PASS", f"{kind}: 私人文件名不在目标里", f"查了 {len(got)} 个文件")

    # 内容路：私人文件的唯一串一个都不许出现
    hits = []
    for rel in got:
        full = installed_docs(dst) / rel
        try:
            text = full.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for marker in PRIVATE.values():
            if marker in text:
                hits.append((rel, marker))
    if hits:
        record("FAIL", f"{kind}: 私人内容不在目标里", f"{hits[:3]}")
    else:
        record("PASS", f"{kind}: 私人内容不在目标里", f"扫了 {len(got)} 个文件 / {len(PRIVATE)} 个唯一串")

    # 源文件与目标文件逐字节一致（装了就要装对）
    diff = []
    for rel in sorted(want & got):
        a = src / rel
        b = installed_docs(dst) / rel
        try:
            if a.read_bytes() != b.read_bytes():
                diff.append(rel)
        except OSError:
            diff.append(rel)
    if diff:
        record("FAIL", f"{kind}: 内容逐字节一致", f"{len(diff)} 个不同: {diff[:3]}")
    else:
        record("PASS", f"{kind}: 内容逐字节一致", f"{len(want & got)} 个文件")

    # 目标里除了 AgentRule/、入口文件、安装器自己的状态目录，不许有别的落盘
    after = snapshot(dst)

    def allowed(p: str) -> bool:
        return (
            p.startswith(".omp/agent/AgentRule/")
            or p == ".omp/agent/AGENTS.md"
            or p.startswith(".agentrule-deploy/")
            or p.startswith(".backup-")
        )

    added = {p for p in after - before if not allowed(p)}
    if added:
        record("FAIL", f"{kind}: 目标里没有多余落盘", f"{sorted(added)[:5]}")
    else:
        record("PASS", f"{kind}: 目标里没有多余落盘", "")


def check_fail_closed(kind: str, build_cmd, mutate, case: str) -> None:
    """mutate(src) 破坏清单；安装器必须退 4 且目标目录保持原样。"""
    with tempfile.TemporaryDirectory(prefix=f"scope-{kind}-{case}-") as td:
        tmp = Path(td)
        src = make_source(tmp)
        dst = tmp / "dst"
        (dst / ".omp" / "agent").mkdir(parents=True)
        mutate(src)
        before = snapshot(dst)
        rc, out = run(build_cmd(src, dst), ROOT)
        after = snapshot(dst)
        if rc != 4:
            record("FAIL", f"{kind}: {case} 退 4", f"rc={rc}")
            print(indent(out, 12))
        else:
            record("PASS", f"{kind}: {case} 退 4", "rc=4")
        if after != before:
            record("FAIL", f"{kind}: {case} 一个文件都不写", f"新增 {sorted(after - before)[:5]}")
        else:
            record("PASS", f"{kind}: {case} 一个文件都不写", "目标目录未变")


def indent(text: str, width: int) -> str:
    pad = " " * width
    return "\n".join(pad + ln for ln in text.strip().splitlines()[:12])


def main() -> int:
    ap = argparse.ArgumentParser(description="安装范围 allowlist 回归测试")
    ap.add_argument("--keep", action="store_true", help="保留临时目录")
    args = ap.parse_args()

    bash = find_bash()
    ps = find_powershell()
    print(f"root  : {ROOT}")
    print(f"bash  : {bash or '(无)'}")
    print(f"ps    : {ps or '(无)'}")
    print()

    if not (ROOT / SCOPE_REL).is_file():
        record("FAIL", "清单存在", f"缺 {ROOT / SCOPE_REL}")
        return 1

    if bash:
        rc, out = run([sys.executable, "scripts/gen-scope.py", "--check"], ROOT)
        if rc == 0:
            record("PASS", "清单与发布树一致", "gen-scope.py --check")
        else:
            record("FAIL", "清单与发布树一致", f"rc={rc}")
            print(indent(out, 12))

    tmpdir = Path(tempfile.mkdtemp(prefix="scope-test-"))
    try:
        if bash:
            src = make_source(tmpdir / "sh")
            dst = src.parent / "dst"
            (dst / ".omp" / "agent").mkdir(parents=True)
            check_install(
                "install.sh",
                [bash, "install/install.sh", "--source", str(src), "--target", str(dst), "--harness", "omp"],
                src,
                dst,
            )
            sh_cmd = lambda s, d: [bash, "install/install.sh", "--source", str(s), "--target", str(d), "--harness", "omp"]
            check_fail_closed("install.sh", sh_cmd, lambda s: (s / SCOPE_REL).unlink(), "清单缺失")
            check_fail_closed("install.sh", sh_cmd, append_entry("../../outside.txt"), "条目含 ..")
            check_fail_closed("install.sh", sh_cmd, append_entry("library/ghost.md"), "条目指向不存在的文件")
            check_fail_closed("install.sh", sh_cmd, comments_only(), "清单为空")
        else:
            record("SKIP", "install.sh", "找不到 bash")

        if ps:
            src = make_source(tmpdir / "ps")
            dst = src.parent / "dst"
            (dst / ".omp" / "agent").mkdir(parents=True)
            check_install(
                "install.ps1",
                [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "install/install.ps1",
                 "--source", str(src), "--target", str(dst), "--harness", "omp"],
                src,
                dst,
            )
            ps_cmd = lambda s, d: [
                ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "install/install.ps1",
                "--source", str(s), "--target", str(d), "--harness", "omp",
            ]
            check_fail_closed("install.ps1", ps_cmd, lambda s: (s / SCOPE_REL).unlink(), "清单缺失")
            check_fail_closed("install.ps1", ps_cmd, append_entry("../../outside.txt"), "条目含 ..")
            check_fail_closed("install.ps1", ps_cmd, append_entry("library/ghost.md"), "条目指向不存在的文件")
            check_fail_closed("install.ps1", ps_cmd, comments_only(), "清单为空")
        else:
            record("SKIP", "install.ps1", "找不到 powershell")
    finally:
        if args.keep:
            print(f"\n临时目录保留: {tmpdir}")
        else:
            shutil.rmtree(tmpdir, ignore_errors=True)

    fails = [r for r in RESULTS if r[0] == "FAIL"]
    skips = [r for r in RESULTS if r[0] == "SKIP"]
    passes = [r for r in RESULTS if r[0] == "PASS"]
    print()
    print(f"[summary] PASS {len(passes)}  FAIL {len(fails)}  SKIP {len(skips)}")
    if fails:
        print("VERDICT: FAIL — 安装范围判据没守住")
        return 1
    if skips:
        print("VERDICT: SKIP — 没有 FAIL，但有安装器没跑（不算通过）")
        return 2
    print("VERDICT: PASS — 清单外的文件进不了目标，失败路径也不写盘")
    return 0


def append_entry(entry: str):
    def mutate(src: Path) -> None:
        p = src / SCOPE_REL
        text = p.read_text(encoding="utf-8")
        p.write_text(text.rstrip("\n") + "\n" + entry + "\n", encoding="utf-8")

    return mutate


def comments_only():
    def mutate(src: Path) -> None:
        (src / SCOPE_REL).write_text("# 空清单\n", encoding="utf-8")

    return mutate


if __name__ == "__main__":
    sys.exit(main())

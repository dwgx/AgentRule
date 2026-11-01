#!/usr/bin/env python3
"""三道门的最小参考实现：只有判据，没有执行位置。

这里每个 `gate_*` 都是纯函数：读一次调用的原始参数，返回 ALLOW 或 DENY。
不读环境、不调模型、不写日志、不 import harness。接进调用点的那层
（拿到原始参数 → 退出 0 / 2）各家自己写，见 ../adapters/README.md。

判据的来历是 ../protocol/00-floor.md 的第 2、3、5 条；
门 id 的登记表在 ../SECURITY.md（7 行表）。
"""

from __future__ import annotations

import posixpath
import re
from typing import NamedTuple


class Decision(NamedTuple):
    allow: bool
    rule: str = ""
    span: str = ""
    fix: str = ""


ALLOW = Decision(True)


def deny(rule: str, span: str, fix: str) -> Decision:
    return Decision(False, rule, span, fix)


# ---------------------------------------------------------------- 路径工具

# 只认这三个 POSIX 根 + Windows 用户 temp 的形状。真门应该读 $TEMP；
# 这里写死是为了夹具在任何机器上给出同一个结果。
TEMP_ROOTS = ("/tmp", "/var/tmp", "/private/tmp")
WIN_USER_TEMP = re.compile(r"^[a-z]:/users/[^/]+/appdata/local/temp(/|$)")

# 解析不出绝对路径的形态：未展开变量、glob、命令替换。
UNRESOLVED = re.compile(r"%[^%\s]+%|\$|\*|\?|\[")


def norm(path: str) -> str:
    """反斜杠转正斜杠、归一化 `..`、统一小写。前缀比较必须在归一化之后做。"""
    return posixpath.normpath(path.replace("\\", "/").strip()).lower()


def is_under_temp(path: str) -> bool:
    p = norm(path)
    if WIN_USER_TEMP.match(p):
        return True
    return any(p == root or p.startswith(root + "/") for root in TEMP_ROOTS)


def is_absolute(path: str) -> bool:
    return path.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", path) is not None


# ---------------------------------------------------------------- 命令切分

def split_segments(command: str) -> list[str]:
    """按未加引号的 `&&` `||` `;` `|` `&` 换行切段。引号里的分隔符不算。"""
    out: list[str] = []
    buf: list[str] = []
    quote = ""
    i = 0
    while i < len(command):
        ch = command[i]
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = ""
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "&" and command[i + 1:i + 2] == "&":
            out.append("".join(buf))
            buf = []
            i += 2
            continue
        if ch == "|" and command[i + 1:i + 2] == "|":
            out.append("".join(buf))
            buf = []
            i += 2
            continue
        if ch in ";|&\n":
            out.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    out.append("".join(buf))
    return [s for s in (seg.strip() for seg in out) if s]


def tokenize(segment: str) -> list[str]:
    out: list[str] = []
    buf: list[str] = []
    quote = ""
    for ch in segment:
        if quote:
            if ch == quote:
                quote = ""
            else:
                buf.append(ch)
        elif ch in "\"'":
            quote = ch
        elif ch.isspace():
            if buf:
                out.append("".join(buf))
                buf = []
        else:
            buf.append(ch)
    if buf:
        out.append("".join(buf))
    return out


ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PREFIX_WORDS = {
    "sudo", "doas", "env", "time", "nohup", "command", "exec", "eval", "nice",
}


def command_word(tokens: list[str]) -> tuple[str, int]:
    """跳过环境赋值和 sudo/env 这类前缀，返回（命令词小写、下标）。"""
    for i, tok in enumerate(tokens):
        if ENV_ASSIGN.match(tok):
            continue
        base = tok.replace("\\", "/").rsplit("/", 1)[-1].lower()
        if base.endswith(".exe"):
            base = base[:-4]
        if base in PREFIX_WORDS:
            continue
        return base, i
    return "", -1


# ---------------------------------------------------------------- 删除方言

PS_VERBS = {"remove-item", "ri", "rd", "rmdir", "del", "erase"}
PS_RECURSE = {"-recurse", "-rec", "-r", "/s"}
PS_FORCE = {"-force", "-fo", "/q"}


def is_switch(tok: str) -> bool:
    if tok.startswith("-"):
        return True
    return re.fullmatch(r"/[A-Za-z]{1,8}", tok) is not None


def rm_flags(args: list[str]) -> tuple[bool, bool]:
    recursive = forced = False
    for arg in args:
        low = arg.lower()
        if low in ("--recursive", "-recurse", "-rec"):
            recursive = True
        elif low in ("--force", "-force", "-fo"):
            forced = True
        elif low.startswith("-") and not low.startswith("--") and len(low) > 1:
            recursive = recursive or "r" in low[1:]
            forced = forced or "f" in low[1:]
    return recursive, forced


def ps_flags(args: list[str]) -> tuple[bool, bool]:
    lows = {arg.lower() for arg in args}
    return bool(lows & PS_RECURSE), bool(lows & PS_FORCE)


# 只在命令串里出现才判：`python -c` 的脚本体不是命令词。
SHUTIL_RMTREE = re.compile(r"shutil\.rmtree\(\s*(?:[rRbB]{1,2})?(['\"])(.+?)\1")


def delete_ops(command: str) -> list[tuple[str, list[str]]]:
    """返回 [(方言, 目标列表)]；没有「递归 + 强制」同时出现时返回空列表。"""
    ops: list[tuple[str, list[str]]] = []
    for segment in split_segments(command):
        tokens = tokenize(segment)
        word, idx = command_word(tokens)
        if word in ("rm",):
            args = tokens[idx + 1:]
            recursive, forced = rm_flags(args)
            dialect = "rm"
        elif word in PS_VERBS:
            args = tokens[idx + 1:]
            recursive, forced = ps_flags(args)
            dialect = word
        else:
            continue
        if not (recursive and forced):
            continue
        ops.append((dialect, [tok for tok in args if not is_switch(tok)]))
    for match in SHUTIL_RMTREE.finditer(command):
        ops.append(("shutil.rmtree", [match.group(2)]))
    return ops


# ---------------------------------------------------------------- 门 1

def gate_recursive_delete(call: dict) -> Decision:
    """判据原文：临时目录外不做递归强删。"""
    ops = delete_ops(call.get("command", ""))
    if not ops:
        return ALLOW
    for dialect, targets in ops:
        if not targets:
            return deny("delete.no-target", dialect, "写绝对路径；解析不出目标就逐条删")
        for target in targets:
            if UNRESOLVED.search(target):
                return deny(
                    "delete.unresolved-target", target,
                    "先把变量展开成绝对路径，再逐条删",
                )
            if not is_absolute(target):
                return deny(
                    "delete.relative-target", target,
                    "写绝对路径；门看不到这次调用的 cwd",
                )
            if not is_under_temp(target):
                return deny(
                    "delete.outside-temp", target,
                    "逐条删；要整棵删就先记副本位置 + sha256",
                )
    return ALLOW


# ---------------------------------------------------------------- 门 2

TEMP_VAR = re.compile(r"%(TMPDIR|TEMP|TMP)%", re.I)


def gate_unexpanded_temp_var(call: dict) -> Decision:
    """判据原文：写入目标带字面 %TEMP% / %TMP% / %TMPDIR%。

    判的是**写入目标**这一个字段：读命令、删除命令、commit 信息不归它管。
    `$TEMP` / `$env:TEMP` 不在这里——那两种由调用方的 shell 展开。
    """
    if call.get("kind") != "write":
        return ALLOW
    path = call.get("path", "")
    match = TEMP_VAR.search(path)
    if not match:
        return ALLOW
    return deny(
        "write.unexpanded-temp-var", match.group(0),
        "写展开后的绝对路径，或让调用方先展开",
    )


# ---------------------------------------------------------------- 门 3

TRAILER = re.compile(
    r"^(co-authored-by|generated-by|assisted-by|made-with|written-by)\s*:\s*(.+)$",
    re.I,
)
BANNER = re.compile(
    r"\b(generated|made|written|created|assisted)\s+(with|by)\s+\[?"
    r"(claude|codex|copilot|cursor|chatgpt|gpt|gemini|aider|windsurf|devin|omp)\b",
    re.I,
)
AGENT_TOKEN = re.compile(
    r"\b(claude|codex|copilot|cursor|chatgpt|gpt|gemini|aider|windsurf|devin|"
    r"anthropic|openai|omp)\b",
    re.I,
)
AGENT_DOMAIN = re.compile(r"@(anthropic|openai|cursor)\.com\b", re.I)


def gate_ai_attribution(call: dict) -> Decision:
    """判据原文：commit 不写 AI 署名。

    只看 commit / tag 信息这一个字段。报告里**引用**署名文本不归它管。
    认三类形态：横幅、trailer、工具邮箱域；人类署名（`Signed-off-by`、
    不在工具名单上的 `Co-Authored-By`）必须放行。
    """
    if call.get("kind") != "commit":
        return ALLOW
    for raw in call.get("message", "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if BANNER.search(line):
            return deny("commit.ai-banner", line[:120], "删掉这行；署名不进 commit")
        trailer = TRAILER.match(line)
        if trailer and (AGENT_TOKEN.search(trailer.group(2))
                        or AGENT_DOMAIN.search(trailer.group(2))):
            return deny(
                "commit.ai-trailer", line[:120],
                "删掉这个 trailer；人类署名用 Signed-off-by",
            )
        if AGENT_DOMAIN.search(line):
            return deny("commit.ai-email", line[:120], "删掉这行")
    return ALLOW


GATES = {
    "recursive-delete": gate_recursive_delete,
    "unexpanded-temp-var": gate_unexpanded_temp_var,
    "ai-attribution": gate_ai_attribution,
}


def judge(gate: str, call: dict) -> Decision:
    try:
        fn = GATES[gate]
    except KeyError:
        raise SystemExit(f"unknown gate: {gate}")
    return fn(call)

[中文](README.md) · [English](README.en.md)

# AgentRule

> EN: What an AI agent must never do, how work is handed off and accepted, and how a session resumes after compaction.

A rulebook for AI agents: which actions are off limits, how to hand a job to another agent and accept it, and how to pick up the thread after the context window is compacted or the session restarts. **Every rule carries the incident that bought it.**

[![version](https://img.shields.io/badge/version-0.1.0-blue)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT%20%2B%20CC--BY--SA--4.0-green)](LICENSE)
[![harness](https://img.shields.io/badge/harness-omp%20%7C%20Codex%20%7C%20Claude%20Code-lightgrey)](adapters/README.md)

> Ten floor rules · six protocol chapters · 17 library write-ups · five adapter pages · ten install files

Most of this repository is written in Chinese. This README, [`docs/60s.en.md`](docs/60s.en.md) and [`protocol/00-floor.en.md`](protocol/00-floor.en.md) are the English entry points; the other links go to the Chinese pages.

**A rule looks like this** ([`protocol/00-floor.en.md`](protocol/00-floor.en.md)):

> **Price a deletion before you make it.** No recursive force-delete outside a temp directory; delete trees
> that contain junctions or other reparse points one entry at a time; before deleting a source, record where
> the copy lives and its sha256; emptying the recycle bin is a separate, announced action.

**A successful install looks like this** (one real run of [`install/verify.sh`](install/verify.sh); the script prints Chinese and the block is verbatim — the counts are from that run, run it yourself for yours):

```text
PASS  docs                     54 files in <target>/.omp/agent/AgentRule
PASS  files                    54/54 个源文件都在且非空
PASS  empty                    0 个 0 字节文件（检查了 54 个）
PASS  entry                    790 bytes / 12 lines，入口块在（agentrule:entry）
PASS  load                     RULES.md 缺失，但 AGENTS.md 入口块在
N/A   hooks                    没有 hooks 目录（未安装 hook，无检查项）
PASS  totals                   lines 11710/11710 (+0.0%)  bytes 673244/673244 (+0.0%)

[summary] PASS 6  FAIL 0  SKIP 0  N/A 1
VERDICT: PASS (exit 0) — 全部检查通过
```

**What a gate catches** (from one real run of [`gates/run.py`](gates/run.py)):

20 fixtures across three gates — `ai-attribution`, `recursive-delete`, `unexpanded-temp-var` — match the reference criteria 20/20. Break one criterion on purpose (`--mutate`, make `is_under_temp()` always true) and 6 fixtures go red, exit 1. **A gate that cannot go red is not a gate.** The 20 fixtures, the pure-function criteria for the three gates, and the 10 boundary rows where another reading flips the verdict are in [`gates/README.md`](gates/README.md) — including **what the fixtures do not prove**: that a gate is installed on your machine, or that it cannot be walked around.

**How much context does the rulebook cost?**

Run [`scripts/budget.py`](scripts/budget.py) and it prints: the entry block (`AGENTS.md`, read every session) 2,599 B, the protocol pages (declared mandatory) 22,221 B, total 24,820 B of 32,768 B (75.7%), 7,948 B left. These are the sizes on an LF checkout — the form the published repo is stored in; a CRLF working copy measures 162 B more (76.2%).

**75.7% is not decoration**: Codex's `project_doc_max_bytes` defaults to 32,768, and anything past it is **silently truncated** — the tail disappears and nothing errors. That is why the entry file holds pointers only and the rules live in pages you open on demand: the 7,948 B left buys about one more chapter, not two. Run the script yourself for your own numbers.

## Who it's for

| You are | You get | Start at |
|---|---|---|
| Someone running omp / Codex / Claude Code | The rulebook installed, plus two acceptance commands | [`install/BOOTSTRAP.md`](install/BOOTSTRAP.md) |
| Someone writing their own agent rules | The source material and the incident archive, opened on demand | [`library/README.md`](library/README.md) |
| Someone who wants machine gates | Criteria and minimal pseudocode, no implementation | [`protocol/03-gates.md`](protocol/03-gates.md) |
| Just curious | The 60-second, zero-install version | [`docs/60s.en.md`](docs/60s.en.md) |

## Getting started

```bash
git clone https://github.com/dwgx/AgentRule.git
cd AgentRule
bash install/install.sh --dry-run     # see the plan; writes nothing
bash install/install.sh               # real install (detects harness and source directory)
bash install/verify.sh                # acceptance; you want to see VERDICT: PASS
```

On Windows use `powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1`, same flags.

**3–5 seconds, zero questions.** The script detects which harness you run and where it lives; it only stops when it cannot.

**If you'd rather not let a script touch anything**: hand the folder to your agent and point it at [`install/BOOTSTRAP.md`](install/BOOTSTRAP.md). That path asks you 9 questions (the list is in [`install/ASK.md`](install/ASK.md)) and takes 15–30 minutes, but you approve every change one by one.

## How it differs

| | What it is | What it governs | What it does not |
|---|---|---|---|
| `AGENTS.md` | Single-file project conventions | How this project is written | Cross-session process, dispatch, acceptance |
| Prompt collections | Snippets | One conversation | Install, rollback, upgrade |
| Hook frameworks | Hard interception | Actions a machine can judge | Judgment rules, context recovery |
| **AgentRule** | Rulebook + deployment protocol | Process, dispatch, recovery, acceptance | Ships no gate code (see [SECURITY.md](SECURITY.md)) |

## What it does not do

- **It does not make you safe.** This is guidance, not enforcement. **There is no security boundary here**: no defense against prompt injection, a malicious skill or MCP server, or your own slip of the hand. See [SECURITY.md](SECURITY.md).
- **It does not update itself.** The repository has no update logic. Upgrade = `git pull` by hand, then re-run acceptance; skip that and you do not know which version is installed. See [`install/UPGRADE.md`](install/UPGRADE.md).
- **It does not install gates for you.** The default install is text only. Hooks are each harness's own mechanism; this repository ships the criteria ([`protocol/03-gates.md`](protocol/03-gates.md)), and you implement the gate.
- **It does not promise your agent will never make a mistake.** It reduces the same mistake happening twice; it does not remove mistakes.
- **It does not touch your code or swap your model.** Install writes only to the harness config directory and a state directory, never to a project.
- **It does not choose for you.** Which harness, user-level or project-level, overwrite or append — you answer; the cost of guessing is written under each question in [`install/ASK.md`](install/ASK.md).

## What the repo looks like

One file belongs to exactly one plane:

- [`install/`](install/INSTALL.md) — the entry. An agent walks in here and is done in four steps
- [`protocol/`](protocol/README.md) — the rules that survive a harness swap (six chapters, ≤400 lines in total, plus an index)
- [`adapters/`](adapters/README.md) — the differences between omp / Codex / Claude Code
- [`library/`](library/README.md) — source material and incident archive; open on demand, never preload
- [`docs/`](docs/60s.en.md) — tutorials, case studies, known gaps
- [`examples/`](examples/brief.md) — two filled-in samples

## Redaction

The source material comes from one real Windows workstation. Paths, hostnames, drive letters and account names were replaced with placeholders; the mapping table is in [`library/README.md`](library/README.md).

The pre-release redaction gate is [`scripts/check-leaks.sh`](scripts/check-leaks.sh). **It ships 12 generic rules**; the five local classes (username, drive letters, private repo names) need your own `leaks.local` passed with `--local`, otherwise it prints `# WARN` at the top and that `TOTAL: 0` does not count. Clean means the last line is `TOTAL: 0` and the exit code is 0.

## Status

**v0.1.0 · first release 2026-11-02 · single maintainer · issues answered on a best-effort basis.**

Known gaps are listed in [`docs/known-gaps.md`](docs/known-gaps.md) (15 items, including "none of the three harnesses has an end-to-end acceptance"). Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

- Code (`install/*.ps1`, `install/*.sh`, `scripts/*`): **MIT**, see [LICENSE](LICENSE).
- Docs (every `*.md`): **CC BY-SA 4.0**, see [LICENSE-docs](LICENSE-docs). Mind the ShareAlike — a modified version you publish must carry the same license.

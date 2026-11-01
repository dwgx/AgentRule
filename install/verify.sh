#!/usr/bin/env bash
# verify.sh — AgentRule 部署后自检（macOS / Linux / Git Bash）
#
# 和 install.sh 的分工：
#   install.sh --verify   逐文件 sha256 比对（装得是不是逐字节一样）
#   verify.sh             部署后健康检查（装进去的东西 harness 到底能不能用）
#                         —— 文件存在且非空 / 规则可加载 / hooks 语法 / 总量在 ±10% 内
#
# 检查项（每个 harness 各跑一遍）：
#   1  docs      规则书目录 <home>/AgentRule/ 存在
#   2  files     源仓库里的每个文件都在目标位置且非空（给了 --source 时）
#   3  empty     已部署的规则书里没有 0 字节文件
#   4  entry     入口文件（AGENTS.md / CLAUDE.md）非空，且有 managed block 或 AgentRule 引用
#   5  load      omp: RULES.md 行数 ≥ --omp-min-lines
#                codex: config.toml 能被 TOML 解析器 parse
#                claude: CLAUDE.md 非空且可加载（与 entry 同判据）
#   6  hooks     hooks/ 存在时：里面至少一个 hook 脚本、非空、语法能过
#   7  totals    总行数 / 总字节与预期（--source 或 --expect-*）相差不超过 --tolerance%
#
# 本脚本只读：不写任何文件、不建目录、不联网。
# 兼容 bash 3.2（macOS 自带）：不用关联数组、不用 ${var,,}、不用 mapfile。
#
# 退出码：
#   0  全部检查通过
#   1  至少一项 FAIL
#   2  没有 FAIL，但至少一项 SKIP（缺工具或缺基线）
#
# 用法：
#   bash verify.sh
#   bash verify.sh --target "$HOME"
#   bash verify.sh --harness omp --source "$HOME/src/agentrule"
#   bash verify.sh --expect-lines 2100 --expect-bytes 240000

set -u

BEGIN_MARK='<!-- BEGIN agentrule:entry v1 -->'
LEGACY_BEGIN_MARK='<!-- BEGIN AgentRule managed block -->'

HARNESS_ORDER='omp codex claude'

PASS_N=0
FAIL_N=0
SKIP_N=0
NA_N=0
FAILED_LIST=''

OPT_TARGET=''
OPT_HARNESS=''
OPT_SOURCE=''
OPT_EXPECT_LINES=''
OPT_EXPECT_BYTES=''
OPT_TOLERANCE=10
OPT_OMP_MIN_LINES=10
OPT_QUIET=0

# ---------------------------------------------------------------- 输出
say() { printf '%s\n' "${1-}"; }

usage() {
  cat <<'USAGE'
AgentRule 部署后自检 (macOS / Linux)

用法:
  bash verify.sh
  bash verify.sh --target "$HOME"
  bash verify.sh --harness omp --source "$HOME/src/agentrule"

参数:
  --target <dir>        安装根目录，默认 = 你的家目录；harness 目录在它下面找
  --harness <h>         omp | codex | claude | all；默认 = 探测到的全部（一个都没有则退出 2）
  --source <dir>        规则书仓库根目录；给了就逐文件核对「存在且非空」并比对总量
  --expect-lines <n>    不给 --source 时，用这个数字当总行数预期
  --expect-bytes <n>    不给 --source 时，用这个数字当总字节预期
  --tolerance <pct>     总量允许偏差，默认 10（即 ±10%）
  --omp-min-lines <n>   omp 的 RULES.md 至少多少行才算「可加载」，默认 10
  --quiet               只打印 FAIL / SKIP 和汇总
  --help, -h            显示本页

退出码:
  0 全部通过 / 1 有 FAIL / 2 没有 FAIL 但有 SKIP（缺工具或缺基线）

本脚本只读：不写文件、不建目录、不联网。
不证明什么：hooks 只查「文件在 / 非空 / 语法过」，不证明它已被 harness 加载或真能拦人；
          规则文件只查「可解析 / 行数」，不证明 harness 已经热加载。
USAGE
}

die_usage() {
  say "错误: $1"
  say ''
  usage
  exit 1
}

need_value() {
  if [ $# -lt 2 ] || [ -z "${2-}" ]; then
    die_usage "$1 需要一个值"
  fi
}

is_uint() {
  case "${1-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

status() { # $1=harness $2=name $3=PASS|FAIL|SKIP $4=detail
  case "$3" in
    PASS) PASS_N=$((PASS_N + 1)) ;;
    FAIL)
      FAIL_N=$((FAIL_N + 1))
      FAILED_LIST="${FAILED_LIST}[$1] $2 — $4
"
      ;;
    SKIP) SKIP_N=$((SKIP_N + 1)) ;;
    N/A) NA_N=$((NA_N + 1)) ;;
  esac
  if [ "$OPT_QUIET" = 0 ] || { [ "$3" != 'PASS' ] && [ "$3" != 'N/A' ]; }; then
    printf '  %-4s  %-24s %s\n' "$3" "$2" "$4"
  fi
}

# ---------------------------------------------------------------- 参数
while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --target) need_value "$arg" "${2-}"; OPT_TARGET="$2"; shift ;;
    --target=*) OPT_TARGET="${arg#*=}" ;;
    --harness) need_value "$arg" "${2-}"; OPT_HARNESS="$2"; shift ;;
    --harness=*) OPT_HARNESS="${arg#*=}" ;;
    --source) need_value "$arg" "${2-}"; OPT_SOURCE="$2"; shift ;;
    --source=*) OPT_SOURCE="${arg#*=}" ;;
    --expect-lines) need_value "$arg" "${2-}"; OPT_EXPECT_LINES="$2"; shift ;;
    --expect-lines=*) OPT_EXPECT_LINES="${arg#*=}" ;;
    --expect-bytes) need_value "$arg" "${2-}"; OPT_EXPECT_BYTES="$2"; shift ;;
    --expect-bytes=*) OPT_EXPECT_BYTES="${arg#*=}" ;;
    --tolerance) need_value "$arg" "${2-}"; OPT_TOLERANCE="$2"; shift ;;
    --tolerance=*) OPT_TOLERANCE="${arg#*=}" ;;
    --omp-min-lines) need_value "$arg" "${2-}"; OPT_OMP_MIN_LINES="$2"; shift ;;
    --omp-min-lines=*) OPT_OMP_MIN_LINES="${arg#*=}" ;;
    --quiet) OPT_QUIET=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die_usage "不认识的参数 '$arg'" ;;
  esac
  shift
done

OPT_HARNESS=$(printf '%s' "$OPT_HARNESS" | tr 'A-Z' 'a-z')
case "$OPT_HARNESS" in
  ''|omp|codex|claude|all) ;;
  *) die_usage "--harness 只接受 omp|codex|claude|all，收到 '$OPT_HARNESS'" ;;
esac

if ! is_uint "$OPT_TOLERANCE" || [ "$OPT_TOLERANCE" -gt 100 ]; then
  die_usage "--tolerance 需要 0..100 的整数，收到 '$OPT_TOLERANCE'"
fi
if ! is_uint "$OPT_OMP_MIN_LINES" || [ "$OPT_OMP_MIN_LINES" -lt 1 ]; then
  die_usage "--omp-min-lines 需要正整数，收到 '$OPT_OMP_MIN_LINES'"
fi
for pair in "expect-lines:$OPT_EXPECT_LINES" "expect-bytes:$OPT_EXPECT_BYTES"; do
  name="${pair%%:*}"
  val="${pair#*:}"
  if [ -n "$val" ] && ! is_uint "$val"; then
    die_usage "--$name 需要非负整数，收到 '$val'"
  fi
done

# ---------------------------------------------------------------- 路径工具
norm_path() {
  p="${1-}"
  case "$p" in
    '~') p="$HOME" ;;
    '~/'*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    [A-Za-z]:\\*) p=$(printf '%s' "$p" | tr '\\' '/') ;;
  esac
  printf '%s' "$p"
}

abspath() {
  ( cd "$1" 2>/dev/null && pwd -P )
}

fbytes() { wc -c < "$1" | tr -d ' \r'; }
flines() { wc -l < "$1" | tr -d ' \r'; }

# 整棵树的总行数/总字节，一次 wc 批量算，避免逐文件 fork（Git Bash 上逐文件 fork 很慢）
tree_totals() { # $1=root -> "lines bytes"
  find "$1" -type f ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.backup*' -exec wc -lc {} + 2>/dev/null \
    | awk '$3 != "total" { l += $1; b += $2 } END { printf "%d %d", l + 0, b + 0 }'
}

pct_fmt() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (b <= 0) { print "n/a" } else { printf "%+.1f%%", (a - b) * 100 / b } }'
}

within_tol() { # actual expected tolerance_pct -> rc 0 = within
  awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { if (b <= 0) exit 1; d = (a - b) / b; if (d < 0) d = -d; exit (d <= t / 100) ? 0 : 1 }'
}

# ---------------------------------------------------------------- 源文件枚举
list_src_files() {
  ( cd "$SRC" && find . -type f \
      ! -path './.git/*' ! -path '*/node_modules/*' ! -path './.backup*' -print ) \
    | sed 's|^\./||'
}

dest_for() { # rel harness_home docs_root
  case "$1" in
    skills/*) printf '%s' "$2/skills/${1#skills/}" ;;
    *) printf '%s' "$3/$1" ;;
  esac
}

# ---------------------------------------------------------------- 外部工具
PY=()
detect_python() {
  for cand in 'python' 'python3' 'py -3'; do
    # shellcheck disable=SC2086
    set -- $cand
    if command -v "$1" >/dev/null 2>&1; then
      if "$@" -c 'import tomllib' >/dev/null 2>&1; then
        PY=("$@")
        return 0
      fi
    fi
  done
  PY=()
  return 1
}

NODE=$(command -v node 2>/dev/null || true)
BUN=$(command -v bun 2>/dev/null || true)
TSC=$(command -v tsc 2>/dev/null || true)

check_syntax() { # $1=path; prints "STATE<TAB>detail"
  case "$1" in
    *.ts)
      if [ -n "$BUN" ]; then
        out=$("$BUN" -e 'const p=process.argv[1];const t=await Bun.file(p).text();new Bun.Transpiler({loader:"ts"}).transformSync(t)' "$1" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
          printf 'PASS\tsyntax ok (bun)'
        else
          msg=$(printf '%s\n' "$out" | awk 'NF { print; exit }')
          printf 'FAIL\tsyntax FAIL (bun): %s' "${msg:-syntax error}"
        fi
        return 0
      fi
      if [ -n "$TSC" ]; then
        out=$("$TSC" --noEmit --skipLibCheck --target ES2022 --module ES2022 --moduleResolution bundler "$1" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
          printf 'PASS\tsyntax ok (tsc)'
        elif printf '%s' "$out" | grep -q 'error TS1[0-9][0-9][0-9]'; then
          msg=$(printf '%s\n' "$out" | grep -m1 'error TS1[0-9][0-9][0-9]')
          printf 'FAIL\tsyntax FAIL (tsc): %s' "$msg"
        else
          printf 'PASS\ttsc 无语法错误（有类型/模块告警，未计为失败）'
        fi
        return 0
      fi
      printf 'SKIP\t没有 bun 也没有 tsc，.ts 语法未检查'
      ;;
    *)
      if [ -z "$NODE" ]; then
        printf 'SKIP\t找不到 node，.js 语法未检查'
        return 0
      fi
      out=$("$NODE" --check "$1" 2>&1)
      rc=$?
      if [ $rc -eq 0 ]; then
        printf 'PASS\tsyntax ok (node --check)'
      else
        msg=$(printf '%s\n' "$out" | awk 'NF { print; exit }')
        printf 'FAIL\tsyntax FAIL (node): %s' "${msg:-syntax error}"
      fi
      ;;
  esac
}

# ---------------------------------------------------------------- 定位
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  */*) SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P) ;;
  *) SCRIPT_DIR=$(pwd -P) ;;
esac

if [ -n "$OPT_SOURCE" ]; then
  SRC=$(abspath "$(norm_path "$OPT_SOURCE")")
  if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    say "错误: --source 指向的目录不存在: $OPT_SOURCE"
    exit 4
  fi
else
  SRC=''
  d="$SCRIPT_DIR"
  k=0
  while [ $k -lt 4 ] && [ -n "$d" ] && [ "$d" != '/' ]; do
    if [ -f "$d/protocol/README.md" ] || [ -f "$d/library/README.md" ] || [ -f "$d/docs/README.md" ]; then
      SRC="$d"
      break
    fi
    nd=$(dirname "$d")
    [ "$nd" = "$d" ] && break
    d="$nd"
    k=$((k + 1))
  done
  if [ -n "$SRC" ] && [ "$(basename "$SRC")" = 'AgentRule' ]; then
    # 从已部署的副本里跑：这份树就是目标本身，不能拿它当基线
    SRC=''
  fi
fi

if [ -n "$OPT_TARGET" ]; then
  TARGET=$(abspath "$(norm_path "$OPT_TARGET")")
else
  TARGET=$(abspath "$HOME")
fi
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  say "错误: 目标根目录不存在: ${OPT_TARGET:-$HOME}"
  exit 4
fi

SRC_N=0
if [ -n "$SRC" ]; then
  SRC_N=$(list_src_files | wc -l | tr -d ' \r')
  if [ "$SRC_N" -eq 0 ]; then
    say "错误: --source 目录里没有文件: $SRC"
    exit 4
  fi
fi

# ---------------------------------------------------------------- harness 选择
probe_exists() {
  case "$1" in
    omp) [ -d "$TARGET/.omp/agent" ] ;;
    codex) [ -d "$TARGET/.codex" ] ;;
    claude) [ -d "$TARGET/.claude" ] ;;
    *) return 1 ;;
  esac
}

home_of() {
  case "$1" in
    omp) printf '%s' "$TARGET/.omp/agent" ;;
    codex) printf '%s' "$TARGET/.codex" ;;
    claude) printf '%s' "$TARGET/.claude" ;;
  esac
}

entry_of() {
  case "$1" in
    omp|codex) printf '%s' "$(home_of "$1")/AGENTS.md" ;;
    claude) printf '%s' "$(home_of "$1")/CLAUDE.md" ;;
  esac
}

SELECTED=''
if [ "$OPT_HARNESS" = 'all' ]; then
  SELECTED="$HARNESS_ORDER"
elif [ -n "$OPT_HARNESS" ]; then
  SELECTED="$OPT_HARNESS"
else
  for h in $HARNESS_ORDER; do
    if probe_exists "$h"; then
      SELECTED="${SELECTED:+$SELECTED }$h"
    fi
  done
fi

detect_python || true

say 'AgentRule post-deploy verify'
say "  script  : $SCRIPT_PATH"
say "  target  : $TARGET"
if [ -n "$SRC" ]; then
  say "  source  : $SRC"
else
  say '  source  : none（总量检查将 SKIP；用 --source 或 --expect-*）'
fi
say "  harness : ${SELECTED:-none}"
say "  tol     : ±$OPT_TOLERANCE%"
if [ ${#PY[@]} -gt 0 ]; then
  say "  python  : ${PY[*]}"
else
  say '  python  : MISSING（codex 的 TOML 解析会 SKIP）'
fi
if [ -n "$NODE" ]; then
  say "  node    : $("$NODE" --version 2>&1)"
else
  say '  node    : MISSING（.js hooks 语法会 SKIP）'
fi
if [ -n "$BUN" ]; then
  say "  bun     : $("$BUN" --version 2>&1)"
else
  say '  bun     : MISSING'
fi
say ''

if [ -z "$SELECTED" ]; then
  say "SKIP  没有发现任何 harness 目录（omp / codex / claude 在 $TARGET 下都不存在）"
  say ''
  say '[summary] PASS 0  FAIL 0  SKIP 1'
  say 'VERDICT: PARTIAL (exit 2) — 没有可检查的 harness'
  exit 2
fi

# ---------------------------------------------------------------- 每个 harness
for h in $SELECTED; do
  HOME_DIR=$(home_of "$h")
  ENTRY=$(entry_of "$h")
  DOCS="$HOME_DIR/AgentRule"

  say "[$h] $HOME_DIR"

  if ! probe_exists "$h"; then
    status "$h" 'home' 'FAIL' "harness 目录不存在: $HOME_DIR"
    say ''
    continue
  fi

  # 1 docs
  DOCS_N=0
  if [ -d "$DOCS" ]; then
    DOCS_N=$(find "$DOCS" -type f ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.backup*' | wc -l | tr -d ' \r')
    status "$h" 'docs' 'PASS' "$DOCS_N files in $DOCS"
  else
    status "$h" 'docs' 'FAIL' "未找到规则书目录: $DOCS"
  fi

  # 2 files
  if [ -n "$SRC" ]; then
    missing=''
    empty=''
    missing_n=0
    empty_n=0
    while IFS= read -r rel; do
      dest=$(dest_for "$rel" "$HOME_DIR" "$DOCS")
      if [ ! -f "$dest" ]; then
        missing_n=$((missing_n + 1))
        if [ "$missing_n" -le 3 ]; then missing="${missing:+$missing, }$rel"; fi
      elif [ ! -s "$dest" ]; then
        empty_n=$((empty_n + 1))
        if [ "$empty_n" -le 3 ]; then empty="${empty:+$empty, }$rel"; fi
      fi
    done < <(list_src_files)
    if [ "$missing_n" -eq 0 ] && [ "$empty_n" -eq 0 ]; then
      status "$h" 'files' 'PASS' "$SRC_N/$SRC_N 个源文件都在且非空"
    else
      detail=''
      if [ "$missing_n" -gt 0 ]; then detail="$missing_n 个缺失: $missing"; fi
      if [ "$empty_n" -gt 0 ]; then
        if [ -n "$detail" ]; then detail="$detail; "; fi
        detail="${detail}$empty_n 个空文件: $empty"
      fi
      status "$h" 'files' 'FAIL' "$detail"
    fi
  else
    if [ ! -f "$DOCS/README.md" ]; then
      status "$h" 'files' 'FAIL' "缺 $DOCS/README.md"
    elif [ ! -s "$DOCS/README.md" ]; then
      status "$h" 'files' 'FAIL' "$DOCS/README.md 是 0 字节"
    else
      status "$h" 'files' 'PASS' 'README.md 存在且非空（未给 --source，只查入口文件）'
    fi
  fi

  # 3 empty
  if [ -d "$DOCS" ]; then
    zero_n=$(find "$DOCS" -type f -size 0 ! -path '*/.git/*' ! -path '*/.backup*' | wc -l | tr -d ' \r')
    if [ "$zero_n" -eq 0 ]; then
      status "$h" 'empty' 'PASS' "0 个 0 字节文件（检查了 $DOCS_N 个）"
    else
      zero_list=$(find "$DOCS" -type f -size 0 ! -path '*/.git/*' ! -path '*/.backup*' | sed "s|^$DOCS/||" | head -5 | tr '\n' ' ' | sed 's/ $//')
      status "$h" 'empty' 'FAIL' "$zero_n 个 0 字节文件: $zero_list"
    fi
  fi

  # 4 entry
  ENTRY_OK=0
  if [ ! -f "$ENTRY" ]; then
    status "$h" 'entry' 'FAIL' "入口文件不存在: $ENTRY"
  elif [ "$(fbytes "$ENTRY")" -eq 0 ]; then
    status "$h" 'entry' 'FAIL' "入口文件是 0 字节: $ENTRY"
  else
    entry_text=$(cat "$ENTRY" 2>/dev/null || true)
    case "$entry_text" in
      *"$BEGIN_MARK"*) entry_ok=1; how='入口块在（agentrule:entry）' ;;
      *"$LEGACY_BEGIN_MARK"*) entry_ok=1; how='入口块在（managed block，旧版）' ;;
      *'BEGIN agentrule:'*|*'BEGIN AgentRule:'*|*'BEGIN AGENTRULE:'*) entry_ok=1; how='入口块在（agentrule:entry）' ;;
      *AgentRule*|*agentrule*|*规则书*) entry_ok=1; how='有 AgentRule 引用' ;;
      *) entry_ok=0; how='' ;;
    esac
    if [ "$entry_ok" = 1 ]; then
      ENTRY_OK=1
      status "$h" 'entry' 'PASS' "$(fbytes "$ENTRY") bytes / $(flines "$ENTRY") lines，$how"
    else
      status "$h" 'entry' 'FAIL' "入口文件在，但没有 managed block / AgentRule 引用: $ENTRY"
    fi
  fi

  # 5 load
  case "$h" in
    omp)
      RULES="$HOME_DIR/RULES.md"
      if [ -f "$RULES" ]; then
        rb=$(fbytes "$RULES")
        rl=$(flines "$RULES")
        if [ "$rb" -eq 0 ]; then
          status "$h" 'load' 'FAIL' 'RULES.md 是 0 字节（omp 没有常驻规则可加载）'
        elif [ "$rl" -lt "$OPT_OMP_MIN_LINES" ]; then
          status "$h" 'load' 'FAIL' "RULES.md 只有 $rl 行，低于 --omp-min-lines $OPT_OMP_MIN_LINES"
        else
          status "$h" 'load' 'PASS' "RULES.md $rl 行 / $rb bytes"
        fi
      elif [ "$ENTRY_OK" = 1 ]; then
        status "$h" 'load' 'PASS' 'RULES.md 缺失，但 AGENTS.md 入口块在（omp 会加载 AGENTS.md）'
      else
        status "$h" 'load' 'FAIL' '既没有 RULES.md，也没有可加载的 AGENTS.md 入口块'
      fi
      ;;
    codex)
      CFG="$HOME_DIR/config.toml"
      if [ ! -f "$CFG" ]; then
        status "$h" 'load' 'FAIL' "config.toml 不存在: $CFG"
      elif [ "$(fbytes "$CFG")" -eq 0 ]; then
        status "$h" 'load' 'FAIL' "config.toml 是 0 字节: $CFG"
      elif [ ${#PY[@]} -eq 0 ]; then
        status "$h" 'load' 'SKIP' '找不到带 tomllib 的 python，config.toml 未解析'
      else
        out=$("${PY[@]}" -c 'import sys,tomllib;tomllib.load(open(sys.argv[1],"rb"))' "$CFG" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
          status "$h" 'load' 'PASS' 'tomllib 解析通过（用户级 config.toml）'
        else
          msg=$(printf '%s\n' "$out" | awk 'NF { last=$0 } END { print last }')
          status "$h" 'load' 'FAIL' "tomllib 解析失败: ${msg:-解析失败（无输出）}"
        fi
      fi
      ;;
    claude)
      if [ "$ENTRY_OK" = 1 ]; then
        status "$h" 'load' 'PASS' "CLAUDE.md $(flines "$ENTRY") 行，可作为全局入口加载"
      else
        status "$h" 'load' 'FAIL' 'CLAUDE.md 不可加载（缺失 / 空 / 没有 AgentRule 引用）'
      fi
      ;;
  esac

  # 6 hooks
  HOOKS="$HOME_DIR/hooks"
  if [ ! -d "$HOOKS" ]; then
    status "$h" 'hooks' 'N/A' '没有 hooks 目录（未安装 hook，无检查项）'
  else
    hook_list=$(find "$HOOKS" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) ! -path '*/.backup*' | sort)
    # 排除备份名
    real_list=''
    real_n=0
    while IFS= read -r hf; do
      [ -n "$hf" ] || continue
      base=$(basename "$hf")
      case "$base" in
        *.bak*|*.before*|*.orig*|*.old*) continue ;;
      esac
      real_list="${real_list}${hf}
"
      real_n=$((real_n + 1))
    done < <(printf '%s\n' "$hook_list")
    if [ "$real_n" -eq 0 ]; then
      status "$h" 'hooks' 'FAIL' "hooks 目录在，但里面没有 .ts/.js hook 脚本: $HOOKS"
    else
      bad=''
      bad_n=0
      skip_list=''
      skip_n=0
      while IFS= read -r hf; do
        [ -n "$hf" ] || continue
        if [ "$(fbytes "$hf")" -eq 0 ]; then
          bad_n=$((bad_n + 1))
          if [ "$bad_n" -le 3 ]; then bad="${bad:+$bad; }$(basename "$hf") 是 0 字节"; fi
          continue
        fi
        res=$(check_syntax "$hf")
        st=${res%%	*}
        dt=${res#*	}
        case "$st" in
          FAIL)
            bad_n=$((bad_n + 1))
            if [ "$bad_n" -le 3 ]; then bad="${bad:+$bad; }$(basename "$hf"): $dt"; fi
            ;;
          SKIP)
            skip_n=$((skip_n + 1))
            skip_list="${skip_list:+$skip_list, }$(basename "$hf")"
            ;;
        esac
      done < <(printf '%s' "$real_list")
      if [ "$bad_n" -gt 0 ]; then
        status "$h" 'hooks' 'FAIL' "$bad"
      elif [ "$skip_n" -gt 0 ]; then
        status "$h" 'hooks' 'SKIP' "$real_n 个 hook 脚本存在且非空，但语法未检查（$skip_list）"
      else
        status "$h" 'hooks' 'PASS' "$real_n 个 hook 脚本：存在 / 非空 / 语法过（未证明已被加载；生效探针设计见 adapters/matrix.md §5.3）"
      fi
    fi
  fi

  # 7 totals
  if [ -n "$SRC" ]; then
    src_tot=$(tree_totals "$SRC")
    src_lines=${src_tot%% *}
    src_bytes=${src_tot##* }
    dep_tot=$(tree_totals "$DOCS")
    dep_lines=${dep_tot%% *}
    dep_bytes=${dep_tot##* }
    # 源仓库若带 skills/，它们装在 <home>/skills/<name>，要并进已部署总量
    if [ -d "$SRC/skills" ]; then
      for sd in "$SRC"/skills/*/; do
        [ -d "$sd" ] || continue
        nm=$(basename "$sd")
        if [ -d "$HOME_DIR/skills/$nm" ]; then
          t=$(tree_totals "$HOME_DIR/skills/$nm")
          dep_lines=$((dep_lines + ${t%% *}))
          dep_bytes=$((dep_bytes + ${t##* }))
        fi
      done
    fi
    if [ "$src_bytes" -le 0 ] || [ "$src_lines" -le 0 ]; then
      status "$h" 'totals' 'SKIP' '源树为空，无法比对总量'
    else
      detail="lines $dep_lines/$src_lines ($(pct_fmt "$dep_lines" "$src_lines"))  bytes $dep_bytes/$src_bytes ($(pct_fmt "$dep_bytes" "$src_bytes"))  tol ±$OPT_TOLERANCE%"
      if within_tol "$dep_lines" "$src_lines" "$OPT_TOLERANCE" && within_tol "$dep_bytes" "$src_bytes" "$OPT_TOLERANCE"; then
        status "$h" 'totals' 'PASS' "$detail"
      else
        status "$h" 'totals' 'FAIL' "$detail"
      fi
    fi
  elif [ -n "$OPT_EXPECT_LINES" ] || [ -n "$OPT_EXPECT_BYTES" ]; then
    dep_tot=$(tree_totals "$DOCS")
    dep_lines=${dep_tot%% *}
    dep_bytes=${dep_tot##* }
    ok=1
    detail=''
    if [ -n "$OPT_EXPECT_LINES" ]; then
      detail="lines $dep_lines/$OPT_EXPECT_LINES ($(pct_fmt "$dep_lines" "$OPT_EXPECT_LINES"))"
      within_tol "$dep_lines" "$OPT_EXPECT_LINES" "$OPT_TOLERANCE" || ok=0
    fi
    if [ -n "$OPT_EXPECT_BYTES" ]; then
      detail="${detail:+$detail  }bytes $dep_bytes/$OPT_EXPECT_BYTES ($(pct_fmt "$dep_bytes" "$OPT_EXPECT_BYTES"))"
      within_tol "$dep_bytes" "$OPT_EXPECT_BYTES" "$OPT_TOLERANCE" || ok=0
    fi
    detail="$detail  tol ±$OPT_TOLERANCE%"
    if [ "$ok" = 1 ]; then
      status "$h" 'totals' 'PASS' "$detail"
    else
      status "$h" 'totals' 'FAIL' "$detail"
    fi
  else
    status "$h" 'totals' 'SKIP' '没有基线（给 --source 或 --expect-lines/--expect-bytes）'
  fi

  say ''
done

# ---------------------------------------------------------------- 汇总
say "[summary] PASS $PASS_N  FAIL $FAIL_N  SKIP $SKIP_N  N/A $NA_N"
if [ "$FAIL_N" -gt 0 ]; then
  printf '%s' "$FAILED_LIST" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    say "  FAILED  $line"
  done
  say "VERDICT: FAIL (exit 1) — $FAIL_N 项检查未通过"
  exit 1
fi
if [ "$SKIP_N" -gt 0 ]; then
  say "VERDICT: PARTIAL (exit 2) — $SKIP_N 项检查被跳过（缺工具或缺基线）"
  exit 2
fi
say 'VERDICT: PASS (exit 0) — 全部检查通过'
exit 0

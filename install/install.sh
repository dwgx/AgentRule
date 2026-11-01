#!/usr/bin/env bash
# install.sh — AgentRule 规则书安装器（macOS / Linux / Git Bash）
#
# 设计原则（和 install.ps1 完全一致，输出格式也一样）：
#   - 不猜：harness / 目标目录 / 冲突，任一不确定就停下来打印 ASK 并退非 0
#   - 不覆盖：默认遇到同名文件只列出，不写
#   - 可回滚：任何覆盖前先备份到 <target>/.backup-<timestamp>/
#   - 不联网：本脚本没有任何下载 / 网络调用
#   - 可验收：--verify 逐文件比对 sha256
#
# 兼容 bash 3.2（macOS 自带），不用关联数组、不用 ${var,,}、不用 mapfile。
#
# 退出码：
#   0  成功 / 无冲突 / --verify 全对
#   2  有冲突，需要用户决定（此时一个文件都没写）
#   3  无法确定 harness（没给 --harness）
#   4  前置条件缺失（target 不存在、harness 目录不存在、源目录找不到）
#   1  用法错误或运行错误

set -u

BEGIN_MARK='<!-- BEGIN agentrule:entry v1 -->'
END_MARK='<!-- END agentrule:entry v1 -->'

HARNESS_ORDER='omp codex claude'

# ---------------------------------------------------------------- 输出
say() { printf '%s\n' "${1-}"; }

usage() {
  cat <<'USAGE'
AgentRule installer (macOS / Linux)

用法:
  bash install.sh --dry-run
  bash install.sh --harness all
  bash install.sh --harness omp --target "$HOME"

参数:
  --dry-run          只报告要做什么，不写任何文件（不建目录、不建备份）
  --harness <h>      omp | codex | claude | all（不给就探测：只命中一套就用它，0 套或多套会停下来问你）
  --target <dir>     安装根目录，默认 = 你的家目录；harness 目录在它下面找
  --force            允许覆盖已有文件（覆盖前先备份）；也允许新建缺失的 harness 目录
  --source <dir>     规则书仓库根目录；默认从脚本所在目录向上找（认 README.md + protocol/ 或 library/）
  --verify           检查已安装内容与源是否一致（sha256 逐文件比对），不写文件
  --help, -h         显示本页

本脚本从不交互提问。需要决定的地方打印 ASK 并退非 0，由 agent 去问用户。

退出码:
  0 成功 / 2 有冲突待决定 / 3 无法确定 harness / 4 前置条件缺失 / 1 用法或运行错误

安装位置（--harness 决定）:
  omp     <target>/.omp/agent/AgentRule/     入口 <target>/.omp/agent/AGENTS.md
  codex   <target>/.codex/AgentRule/         入口 <target>/.codex/AGENTS.md
  claude  <target>/.claude/AgentRule/        入口 <target>/.claude/CLAUDE.md
USAGE
}

die_usage() {
  say "错误: $1"
  say ''
  usage
  exit 1
}

# ---------------------------------------------------------------- 参数
OPT_DRY=0
OPT_HARNESS=''
OPT_TARGET=''
OPT_FORCE=0
OPT_SOURCE=''
OPT_VERIFY=0
AUTO_PICKED=0

need_value() {
  if [ $# -lt 2 ] || [ -z "${2-}" ]; then
    die_usage "$1 需要一个值"
  fi
}

while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --dry-run|-n|--dryrun) OPT_DRY=1 ;;
    --harness) need_value "$arg" "${2-}"; OPT_HARNESS="$2"; shift ;;
    --harness=*) OPT_HARNESS="${arg#*=}" ;;
    --target) need_value "$arg" "${2-}"; OPT_TARGET="$2"; shift ;;
    --target=*) OPT_TARGET="${arg#*=}" ;;
    --force) OPT_FORCE=1 ;;
    --source) need_value "$arg" "${2-}"; OPT_SOURCE="$2"; shift ;;
    --source=*) OPT_SOURCE="${arg#*=}" ;;
    --verify) OPT_VERIFY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die_usage "不认识的参数 '$arg'" ;;
  esac
  shift
done

if [ -n "$OPT_HARNESS" ]; then
  OPT_HARNESS="$(printf '%s' "$OPT_HARNESS" | tr '[:upper:]' '[:lower:]')"
  case "$OPT_HARNESS" in
    omp|codex|claude|all) : ;;
    *) die_usage "--harness 只接受 omp|codex|claude|all，收到 '$OPT_HARNESS'" ;;
  esac
fi

# ---------------------------------------------------------------- 路径工具
abspath() {
  # 目录/文件都可；不存在的路径用 pwd -P 的父目录拼
  if [ -d "$1" ]; then
    ( cd "$1" && pwd -P )
  else
    d="$(dirname -- "$1")"
    b="$(basename -- "$1")"
    if [ -d "$d" ]; then printf '%s/%s\n' "$(cd "$d" && pwd -P)" "$b"; else printf '%s\n' "$1"; fi
  fi
}

expand_home() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

trim_slash() {
  printf '%s\n' "${1%/}"
}

sha256_of() {
  if [ ! -f "$1" ]; then printf '\n'; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | sed 's/.*= //'
  else
    # 没有任何 sha256 工具：退化为字节数（输出里会注明）
    printf '%s\n' "$(wc -c < "$1" | tr -d ' ')"
  fi
}

find_source_root() {
  start="$1"
  p1="$(dirname -- "$start")"
  p2="$(dirname -- "$p1")"
  best=''
  best_score=0
  for c in "$start" "$p1" "$p2"; do
    [ -n "$c" ] || continue
    [ -d "$c" ] || continue
    [ -f "$c/README.md" ] || continue
    has_marker=0
    for m in protocol/00-floor.md library/floor/hard-floor.md 01-floor/hard-floor.md 01-floor/硬地板.md docs/hard-floor.md docs/硬地板.md; do
      if [ -f "$c/$m" ]; then has_marker=1; break; fi
    done
    [ "$has_marker" = 1 ] || continue
    # 第三个交叉证据：CHANGELOG.md 在仓库根，有它就优先（老 staging 树没有）
    score=1
    if [ -f "$c/CHANGELOG.md" ]; then score=2; fi
    if [ "$score" -gt "$best_score" ]; then
      best_score="$score"
      best="$c"
    fi
  done
  [ -n "$best" ] || return 1
  ( cd "$best" && pwd -P )
}

# ---------------------------------------------------------------- 定位
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$0")"

if [ -n "$OPT_SOURCE" ]; then
  SOURCE_ROOT="$(abspath "$(expand_home "$OPT_SOURCE")")"
  if [ ! -d "$SOURCE_ROOT" ]; then
    say "错误: --source 指向的目录不存在: $SOURCE_ROOT"
    exit 4
  fi
else
  if ! SOURCE_ROOT="$(find_source_root "$SCRIPT_DIR")"; then
    say '错误: 找不到规则书源目录（脚本所在目录及其上两级都没有 README.md + protocol/ 或 library/）。'
    say '     用 --source <仓库根目录> 指定。'
    say ''
    say 'ASK（问用户，不要猜）:'
    say '  这个仓库解压/克隆到哪个目录了？把那个目录用 --source 传给我。'
    exit 4
  fi
fi

if [ -n "$OPT_TARGET" ]; then
  TARGET_ROOT="$(abspath "$(expand_home "$OPT_TARGET")")"
else
  TARGET_ROOT="$(abspath "$HOME")"
fi
TARGET_ROOT="$(trim_slash "$TARGET_ROOT")"

if [ ! -d "$TARGET_ROOT" ]; then
  say "错误: 目标根目录不存在: $TARGET_ROOT"
  say ''
  say 'ASK（问用户，不要猜）:'
  say "  你的家目录是 $TARGET_ROOT 吗？不是的话用 --target <家目录> 指定；"
  say '  如果这个目录还不存在，先建它（本脚本不替你造家目录）。'
  exit 4
fi

if [ "$TARGET_ROOT" = "$SOURCE_ROOT" ]; then
  say "错误: --target 和源目录是同一个（$TARGET_ROOT）。会把装好的文件再当成源复制一遍。"
  exit 4
fi

case "$TARGET_ROOT/" in
  "$SOURCE_ROOT"/*)
    say "错误: --target 落在源目录里面（$TARGET_ROOT）。会把装好的文件再当成源复制一遍。"
    exit 4
    ;;
esac

# ---------------------------------------------------------------- 源文件清单
FILES=()
while IFS= read -r -d '' f; do
  rel="${f#"$SOURCE_ROOT"/}"
  [ -n "$rel" ] || continue
  case "/$rel/" in
    */.git/*|*/node_modules/*) continue ;;
  esac
  case "$rel" in
    .backup-*) continue ;;
  esac
  FILES+=("$rel")
done < <(find "$SOURCE_ROOT" -type f -print0)

if [ ${#FILES[@]} -eq 0 ]; then
  say "错误: 源目录里没有可安装的文件: $SOURCE_ROOT"
  exit 4
fi

# 排序（LC_ALL=C 保证两台机器输出一致）
SORTED=()
while IFS= read -r rel; do
  [ -n "$rel" ] && SORTED+=("$rel")
done < <(printf '%s\n' "${FILES[@]}" | LC_ALL=C sort)
FILES=("${SORTED[@]}")

FILE_COUNT=${#FILES[@]}

# ---------------------------------------------------------------- harness 探测
probe_home() {
  case "$1" in
    omp) printf '%s/.omp/agent\n' "$TARGET_ROOT" ;;
    codex) printf '%s/.codex\n' "$TARGET_ROOT" ;;
    claude) printf '%s/.claude\n' "$TARGET_ROOT" ;;
  esac
}

probe_entry_name() {
  case "$1" in
    claude) printf 'CLAUDE.md\n' ;;
    *) printf 'AGENTS.md\n' ;;
  esac
}

probe_entry() {
  printf '%s/%s\n' "$(probe_home "$1")" "$(probe_entry_name "$1")"
}

FOUND=''
for h in $HARNESS_ORDER; do
  if [ -d "$(probe_home "$h")" ]; then FOUND="$FOUND $h"; fi
done
FOUND="${FOUND# }"

print_probe() {
  for h in $HARNESS_ORDER; do
    home="$(probe_home "$h")"
    if [ -d "$home" ]; then state='FOUND    '; else state='MISSING  '; fi
    mark=''
    case " $SELECTED " in *" $h "*) mark=' *' ;; esac
    printf '  %-8s%s%s%s\n' "$h" "$state" "$home" "$mark"
  done
}

# ---------------------------------------------------------------- 决定 harness
if [ -z "$OPT_HARNESS" ]; then
  # ASK.md Q1 默认：探测只命中一套就用它；0 套或多套必须问
  FOUND_COUNT=0
  for h in $HARNESS_ORDER; do
    if [ -d "$(probe_home "$h")" ]; then FOUND_COUNT=$((FOUND_COUNT + 1)); fi
  done
  if [ "$FOUND_COUNT" -eq 1 ]; then
    OPT_HARNESS="$FOUND"
    AUTO_PICKED=1
  else
    say 'AgentRule installer'
    if [ "$OPT_DRY" = 1 ]; then say '  mode    : DRY-RUN（不写任何文件）'; else say '  mode    : APPLY'; fi
    say "  source  : $SOURCE_ROOT"
    say "  target  : $TARGET_ROOT"
    say ''
    say '[detect] harness 目录'
    SELECTED=''
    print_probe
    say ''
    say '错误: 没给 --harness，而且探测不出唯一一套，我不替你挑。'
    say ''
    say 'ASK（把这些原样问用户，不要自己决定）:'
    say '  1. 你的 agent 用哪套 harness？可选: omp / codex / claude / all'
    if [ -n "$FOUND" ]; then say "     探测结果: $FOUND"; else say '     探测结果: 一个都没找到（可能装在家目录以外的地方）'; fi
    say "  2. 家目录是不是 $TARGET_ROOT ？不是就告诉我路径，我用 --target 传进去。"
    say '  3. 要不要先看计划？先跑 --dry-run 再决定。'
    say ''
    say '确定后重跑，例如:'
    say "  bash \"$SCRIPT_PATH\" --harness all --target \"$TARGET_ROOT\" --dry-run"
    exit 3
  fi
fi

if [ "$OPT_HARNESS" = 'all' ]; then SELECTED="$HARNESS_ORDER"; else SELECTED="$OPT_HARNESS"; fi

# 防自嵌套：源 = 已安装的 AgentRule 目录时，重复运行必须是 no-op，不能长出 AgentRule/AgentRule
for h in $SELECTED; do
  docs_full="$(abspath "$(probe_home "$h")/AgentRule")"
  if [ "$SOURCE_ROOT" != "$docs_full" ]; then
    case "$SOURCE_ROOT/" in
      "$docs_full"/*)
        say "错误: 源目录在目标里面（源 $SOURCE_ROOT，目标 $docs_full）。这样会复制出 AgentRule/AgentRule。"
        say '     如果你是从已安装的副本重跑，--target 应该是家目录，不是 AgentRule 目录本身。'
        exit 4
        ;;
    esac
    case "$docs_full/" in
      "$SOURCE_ROOT"/*)
        say "错误: 目标在源目录里面（源 $SOURCE_ROOT，目标 $docs_full）。"
        exit 4
        ;;
    esac
  fi
done

MISSING=''
for h in $SELECTED; do
  if [ ! -d "$(probe_home "$h")" ]; then MISSING="$MISSING $h"; fi
done
MISSING="${MISSING# }"

if [ -n "$MISSING" ] && [ "$OPT_FORCE" != 1 ]; then
  say 'AgentRule installer'
  if [ "$OPT_DRY" = 1 ]; then say '  mode    : DRY-RUN（不写任何文件）'; else say '  mode    : APPLY'; fi
  say "  source  : $SOURCE_ROOT"
  say "  target  : $TARGET_ROOT"
  say ''
  say '[detect] harness 目录'
  print_probe
  say ''
  say '错误: 你指定的 harness 目录不存在，我不替你建（可能装在家目录以外）。'
  for h in $MISSING; do say "  缺失: $h -> $(probe_home "$h")"; done
  say ''
  say 'ASK（把这些原样问用户，不要自己决定）:'
  say '  1. 这个 harness 装在别的地方吗？给我那个目录，我用 --target 指过去。'
  say '  2. 还是确实没装、先要这套规则书？确认后加 --force，我会新建目录。'
  exit 4
fi

# ---------------------------------------------------------------- 入口块
entry_block() {
  h="$1"
  case "$h" in
    omp)
      home_rel='~/.omp/agent'
      extra='- 这套 harness 的 hooks 在 `~/.omp/agent/hooks/`，skills 在 `~/.omp/agent/skills/`；本文件是全局 `AGENTS.md`。'
      ;;
    codex)
      home_rel='~/.codex'
      extra='- 这套 harness 的全局配置是 `~/.codex/config.toml`，本文件是全局 `AGENTS.md`。'
      ;;
    claude)
      home_rel='~/.claude'
      extra='- 这套 harness 的全局入口就是本文件 `CLAUDE.md`，项目级配置在 `.claude/`。'
      ;;
  esac
  doc_rel="$home_rel/AgentRule"
  cat <<EOF
$BEGIN_MARK
## AgentRule（已安装的规则书）

规则书在 \`$doc_rel/\`。**不要整目录预载**：先读 \`AgentRule/README.md\`，按里面的 W/S 档顺序按需开页。

- 常驻只放铁律和入口；用到哪篇打开哪篇。
- 这份规则书是 guidance，不是 enforcement；真正拦人的是本 harness 自己的 hook 和配置。
$extra
- 首行只写 \`STATUS:\`；没跑过的东西标 \`[UNVERIFIED]\`。
- 部署/安装这类会改用户机器的活：不确定就问用户，不要猜。
- 装了哪些文件、怎么验收：\`$doc_rel/README.md\` 的文件地图。
$END_MARK
EOF
}

test_entry_size() {
  # $1 harness, $2 entry path；返回 0 = 没问题，1 = 会被静默截断
  th="$1"
  entry="$2"
  if [ ! -f "$entry" ]; then return 1; fi
  size="$(wc -c < "$entry" | tr -d ' ')"
  note=''
  ok=0
  if [ "$size" -gt 32768 ]; then
    if [ "$th" = 'codex' ]; then
      limit=0
      limit_found=0
      cfg="$(probe_home codex)/config.toml"
      if [ -f "$cfg" ]; then
        limit="$(grep -E '^[[:space:]]*project_doc_max_bytes[[:space:]]*=[[:space:]]*[0-9]+' "$cfg" | head -1 | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/')"
        if [ -n "$limit" ]; then limit_found=1; else limit=0; fi
      fi
      if [ "$limit" -lt "$size" ]; then
        ok=1
        if [ "$limit_found" = 1 ]; then
          note="   WARN: > 32768 B，Codex 会静默截断尾部（config.toml 的 project_doc_max_bytes=$limit）"
        else
          note="   WARN: > 32768 B，Codex 会静默截断尾部（config.toml 未设 project_doc_max_bytes，默认 32768）"
        fi
      else
        note="   (config.toml 已放大到 $limit B)"
      fi
    else
      note='   (本 harness 无此上限，仅报告大小)'
    fi
  fi
  printf '  [entry-size] %-7s%s B  %s%s\n' "$th" "$size" "$entry" "$note"
  return "$ok"
}

show_truncation_fix() {
  say '  WARN: 入口文件超过 32768 B，Codex 只会读前 32768 B，尾部消失且不报错。'
  say '        修法一: 在 ~/.codex/config.toml 加 project_doc_max_bytes = 65536'
  say '        修法二: 入口只留指针，规则分篇放 AgentRule/（本安装器就是这么做的）'
  say '        注意: 项目级 .codex/config.toml 只在 trust_level 落盘后生效，别只改项目级。'
}

strip_block() {
  awk '
    /<!-- BEGIN agentrule:entry v1 -->/ { skip=1; next }
    /<!-- END agentrule:entry v1 -->/ { skip=0; next }
    !skip { print }
  ' "$1"
}

compose_entry() {
  # $1 = 现有文件（可能不存在），$2 = 入口块；结果写 stdout
  existing_path="$1"
  block="$2"
  if [ ! -f "$existing_path" ]; then
    printf '%s\n' "$block"
    return 0
  fi
  stripped="$(strip_block "$existing_path")"
  if [ -n "$stripped" ]; then
    printf '%s\n\n%s\n' "$stripped" "$block"
  else
    printf '%s\n' "$block"
  fi
}

# ---------------------------------------------------------------- 计划
PLAN=()
add_plan() {
  # 用 US (0x1f) 分隔：TAB 是 IFS 空白，空字段会被吞掉导致字段错位（entries 的 src 就是空的）
  PLAN+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"$'\x1f'"$5"$'\x1f'"$6")
}

for h in $SELECTED; do
  home="$(probe_home "$h")"
  docs_dest="$home/AgentRule"
  for rel in "${FILES[@]}"; do
    src_full="$SOURCE_ROOT/$rel"
    dest="$docs_dest/$rel"
    if [ -d "$dest" ]; then
      add_plan "$h" 'CONFLICT' "$rel" "$src_full" "$dest" '目标是目录'
      continue
    fi
    if [ ! -e "$dest" ]; then
      add_plan "$h" 'CREATE' "$rel" "$src_full" "$dest" ''
      continue
    fi
    if [ "$(sha256_of "$src_full")" = "$(sha256_of "$dest")" ]; then
      add_plan "$h" 'SAME' "$rel" "$src_full" "$dest" ''
    elif [ "$OPT_FORCE" = 1 ]; then
      add_plan "$h" 'BACKUP+WRITE' "$rel" "$src_full" "$dest" '内容不同，先备份再覆盖'
    else
      add_plan "$h" 'CONFLICT' "$rel" "$src_full" "$dest" '内容不同；默认不覆盖'
    fi
  done

  entry="$(probe_entry "$h")"
  entry_name="$(probe_entry_name "$h")"
  block="$(entry_block "$h")"
  if [ ! -e "$entry" ]; then
    add_plan "$h" 'ENTRY_CREATE' "$entry_name" '' "$entry" '新建入口文件'
  else
    if [ "$(compose_entry "$entry" "$block")" = "$(cat "$entry")" ]; then
      add_plan "$h" 'ENTRY_SAME' "$entry_name" '' "$entry" ''
    elif [ "$OPT_FORCE" = 1 ]; then
      add_plan "$h" 'ENTRY_UPDATE' "$entry_name" '' "$entry" '先备份再写入口块'
    else
      add_plan "$h" 'ENTRY_CONFLICT' "$entry_name" '' "$entry" '入口文件已有内容；需要 --force 才追加'
    fi
  fi
done

# ---------------------------------------------------------------- 统计
COUNT_CREATE=0
COUNT_OVERWRITE=0
COUNT_SAME=0
COUNT_CONFLICT=0
COUNT_ENTRY=0
for line in "${PLAN[@]}"; do
  IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
  case "$pkind" in
    CREATE) COUNT_CREATE=$((COUNT_CREATE + 1)) ;;
    BACKUP+WRITE) COUNT_OVERWRITE=$((COUNT_OVERWRITE + 1)) ;;
    SAME|ENTRY_SAME) COUNT_SAME=$((COUNT_SAME + 1)) ;;
    CONFLICT|ENTRY_CONFLICT) COUNT_CONFLICT=$((COUNT_CONFLICT + 1)) ;;
  esac
  case "$pkind" in
    ENTRY_*) COUNT_ENTRY=$((COUNT_ENTRY + 1)) ;;
  esac
done

# ---------------------------------------------------------------- 打印计划
say 'AgentRule installer'
if [ "$OPT_DRY" = 1 ]; then say '  mode    : DRY-RUN（不写任何文件）'
elif [ "$OPT_VERIFY" = 1 ]; then say '  mode    : VERIFY（只比对，不写）'
else say '  mode    : APPLY'; fi
say "  script  : $SCRIPT_PATH"
say "  source  : $SOURCE_ROOT"
say "  target  : $TARGET_ROOT"
say "  harness : $(printf '%s' "$SELECTED" | sed 's/ /, /g')"
if [ "$AUTO_PICKED" = 1 ]; then
  say "  note    : 没给 --harness；探测到唯一一套 $OPT_HARNESS，按 install/ASK.md Q1 的默认值使用（要改就加 --harness）"
fi
say '  network : 不使用（脚本里没有任何下载调用）'
say ''
say '[detect] harness 目录'
print_probe
say ''

if [ "$OPT_VERIFY" = 1 ]; then
  say "[verify] 源 $FILE_COUNT 个文件"
  BAD=0
  for line in "${PLAN[@]}"; do
    IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
    case "$pkind" in
      SAME|ENTRY_SAME) state='OK' ;;
      CREATE|ENTRY_CREATE) state='MISSING'; BAD=$((BAD + 1)) ;;
      *) state='DRIFT'; BAD=$((BAD + 1)) ;;
    esac
    printf '  %-7s%-8s%s\n' "$ph" "$state" "$prel"
  done
  say ''
  SIZE_BAD=0
  for h in $SELECTED; do
    if ! test_entry_size "$h" "$(probe_entry "$h")"; then SIZE_BAD=1; fi
  done
  if [ "$SIZE_BAD" = 1 ]; then show_truncation_fix; fi
  BAD=$((BAD + SIZE_BAD))
  say ''
  say "[summary] ok $COUNT_SAME  bad $BAD"
  if [ "$BAD" -eq 0 ]; then
    say '结果: 安装内容与源一致，入口文件没超截断线。'
    exit 0
  fi
  say '结果: 有缺失、不一致或入口超限。重跑安装（不带 --verify）可补齐；冲突项要 --force。'
  exit 2
fi

say "[files] 每个 harness 要处理 $FILE_COUNT 个文件"
for h in $SELECTED; do
  say "  -- $h --"
  for line in "${PLAN[@]}"; do
    IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
    [ "$ph" = "$h" ] || continue
    case "$pkind" in ENTRY_*) continue ;; esac
    if [ -n "$pnote" ]; then
      printf '  %-14s%s   (%s)\n' "$pkind" "$prel" "$pnote"
    else
      printf '  %-14s%s\n' "$pkind" "$prel"
    fi
  done
  for line in "${PLAN[@]}"; do
    IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
    [ "$ph" = "$h" ] || continue
    case "$pkind" in ENTRY_*) : ;; *) continue ;; esac
    entry_rel="${pdest#"$TARGET_ROOT"/}"
    if [ -n "$pnote" ]; then
      printf '  %-14s%s   (%s)\n' "$pkind" "$entry_rel" "$pnote"
    else
      printf '  %-14s%s\n' "$pkind" "$entry_rel"
    fi
    break
  done
done
say ''

# 将新建的目录
NEWDIRS=''
for line in "${PLAN[@]}"; do
  IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
  case "$pkind" in CREATE|BACKUP+WRITE|ENTRY_CREATE|ENTRY_UPDATE) : ;; *) continue ;; esac
  d="$(dirname -- "$pdest")"
  while [ -n "$d" ] && [ "${#d}" -gt "${#TARGET_ROOT}" ] && [ ! -d "$d" ]; do
    case "|$NEWDIRS|" in *"|$d|"*) : ;; *) NEWDIRS="$NEWDIRS|$d" ;; esac
    d="$(dirname -- "$d")"
  done
done
if [ -n "$NEWDIRS" ]; then
  say '[dirs] 将新建'
  printf '%s\n' "$NEWDIRS" | tr '|' '\n' | LC_ALL=C sort | while IFS= read -r d; do
    [ -n "$d" ] && say "  ${d#"$TARGET_ROOT"/}"
  done
  say ''
fi

say '[summary]'
say "  create $COUNT_CREATE  overwrite $COUNT_OVERWRITE  same $COUNT_SAME  conflict $COUNT_CONFLICT  entry $COUNT_ENTRY"
say ''

if [ "$COUNT_CONFLICT" -gt 0 ]; then
  say '[conflict] 这些目标已存在且内容不同，默认不覆盖:'
  for line in "${PLAN[@]}"; do
    IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
    case "$pkind" in CONFLICT|ENTRY_CONFLICT) say "  $pdest" ;; esac
  done
  say ''
  say 'ASK（把这些原样问用户，不要自己决定）:'
  say "  有 $COUNT_CONFLICT 个文件会被覆盖。要覆盖吗？"
  say '  覆盖 = 先把原文件备份到 <target>/.backup-<时间戳>/，再写新内容。'
  say '  同意覆盖: 加 --force 重跑。'
  say '  只想补齐缺的: 先手动挪走上面列出的文件，再重跑。'
  say ''
  if [ "$OPT_DRY" = 1 ]; then
    say "结果: DRY-RUN，没有写任何文件；上面 $COUNT_CONFLICT 个冲突需要用户决定。"
  else
    say '结果: 没有写任何文件（冲突待决定）。'
  fi
  exit 2
fi

if [ "$OPT_DRY" = 1 ]; then
  say "[manifest] 真跑时会写: $TARGET_ROOT/.agentrule-deploy/<run-id>/manifest.json（卸载靠它）"
  say ''
  say '结果: DRY-RUN，没有写任何文件。去掉 --dry-run 即按上面执行。'
  say ''
  say '验收命令（装完后跑）:'
  say "  bash \"$SCRIPT_DIR/install.sh\" --verify --harness $OPT_HARNESS --target \"$TARGET_ROOT\""
  exit 0
fi

# ---------------------------------------------------------------- 执行
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$TARGET_ROOT/.backup-$STAMP"
STATE_DIR="$TARGET_ROOT/.agentrule-deploy/$STAMP"
BACKUP_COUNT=0
WRITTEN=0
STEP_NO=0

J_FILES=()
J_ENTRIES=()
LOG_LINES=()
BEFORE_PATHS=()
BEFORE_VALS=()
BK_FILES=()
BK_PATHS=()

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

BACKUP_PATH=''
backup_one() {
  # $1 = 源文件, $2 = 相对 target 的路径；结果放 BACKUP_PATH。
  # 不能用命令替换调用：子 shell 里的 BACKUP_COUNT 会丢。
  BACKUP_PATH="$BACKUP_ROOT/$2"
  mkdir -p "$(dirname -- "$BACKUP_PATH")"
  cp -p "$1" "$BACKUP_PATH"
  BACKUP_COUNT=$((BACKUP_COUNT + 1))
}

lookup_before() {
  li=0
  while [ "$li" -lt ${#BEFORE_PATHS[@]} ]; do
    if [ "${BEFORE_PATHS[$li]}" = "$1" ]; then printf '%s' "${BEFORE_VALS[$li]}"; return 0; fi
    li=$((li + 1))
  done
  printf ''
}

lookup_backup() {
  li=0
  while [ "$li" -lt ${#BK_FILES[@]} ]; do
    if [ "${BK_FILES[$li]}" = "$1" ]; then printf '%s' "${BK_PATHS[$li]}"; return 0; fi
    li=$((li + 1))
  done
  printf ''
}

log_line() {
  # $1 id, $2 action, $3 path, $4 before, $5 after
  LOG_LINES+=("$(date +%Y-%m-%dT%H:%M:%S%z) | $1 | $2 | $3 | before=$4 | after=$5 | ok")
}

for line in "${PLAN[@]}"; do
  IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
  case "$pkind" in
    CREATE|BACKUP+WRITE|ENTRY_CREATE|ENTRY_UPDATE) : ;;
    *) continue ;;
  esac
  STEP_NO=$((STEP_NO + 1))
  sid="S$STEP_NO"

  case "$pkind" in
    ENTRY_*)
      before=''
      backup_path=''
      if [ -f "$pdest" ]; then
        before="$(sha256_of "$pdest")"
        backup_one "$pdest" "${pdest#"$TARGET_ROOT"/}"
        backup_path="$BACKUP_PATH"
      fi
      mkdir -p "$(dirname -- "$pdest")"
      new_text="$(compose_entry "$pdest" "$(entry_block "$ph")")"
      printf '%s\n' "$new_text" > "$pdest"
      after="$(sha256_of "$pdest")"
      BEFORE_PATHS+=("$pdest"); BEFORE_VALS+=("$before")
      if [ -n "$backup_path" ]; then BK_FILES+=("${pdest#"$TARGET_ROOT"/}"); BK_PATHS+=("$backup_path"); fi
      log_line "$sid" 'append-block' "$pdest" "$before" "$after"
      WRITTEN=$((WRITTEN + 1))
      ;;
    *)
      before=''
      backup_path=''
      action='create'
      if [ -f "$pdest" ]; then
        action='overwrite'
        before="$(sha256_of "$pdest")"
        backup_one "$pdest" "${pdest#"$TARGET_ROOT"/}"
        backup_path="$BACKUP_PATH"
      fi
      mkdir -p "$(dirname -- "$pdest")"
      cp -p "$psrc" "$pdest"
      after="$(sha256_of "$pdest")"
      BEFORE_PATHS+=("$pdest"); BEFORE_VALS+=("$before")
      if [ -n "$backup_path" ]; then BK_FILES+=("${pdest#"$TARGET_ROOT"/}"); BK_PATHS+=("$backup_path"); fi
      log_line "$sid" 'write-file' "$pdest" "$before" "$after"
      WRITTEN=$((WRITTEN + 1))
      ;;
  esac
done

# manifest 描述「装完之后的完整状态」，不是「这一次写了哪几个」——
# 卸载要按它删/还原，只记增量会让后一次 --force 覆盖掉前一次的清单。
for line in "${PLAN[@]}"; do
  IFS=$'\x1f' read -r ph pkind prel psrc pdest pnote <<< "$line"
  case "$pkind" in CONFLICT|ENTRY_CONFLICT) continue ;; esac
  [ -f "$pdest" ] || continue
  msha="$(sha256_of "$pdest")"
  mbk="$(lookup_backup "${pdest#"$TARGET_ROOT"/}")"
  case "$pkind" in
    ENTRY_*)
      mbefore="$(lookup_before "$pdest")"
      J_ENTRIES+=("{\"path\": \"$(json_escape "$pdest")\", \"block_id\": \"entry\", \"version\": \"v1\", \"before_sha256\": \"$mbefore\", \"after_sha256\": \"$msha\", \"backup\": \"$(json_escape "$mbk")\"}")
      ;;
    *)
      case "$pkind" in
        CREATE) maction='create' ;;
        BACKUP+WRITE) maction='overwrite' ;;
        *) maction='unchanged' ;;
      esac
      J_FILES+=("{\"path\": \"$(json_escape "$pdest")\", \"action\": \"$maction\", \"sha256\": \"$msha\", \"backup\": \"$(json_escape "$mbk")\"}")
      ;;
  esac
done

# manifest + apply.log：卸载和回滚靠它，不靠记忆（协议 §6.1 / §6.3）
mkdir -p "$STATE_DIR"
MANIFEST="$STATE_DIR/manifest.json"

harness_json=''
for h in $SELECTED; do
  if [ -n "$harness_json" ]; then harness_json="$harness_json, "; fi
  harness_json="$harness_json\"$h\""
done

if [ "$BACKUP_COUNT" -gt 0 ]; then backup_json="$BACKUP_ROOT"; else backup_json=''; fi

{
  printf '{\n'
  printf '  "protocol": "ADP-1",\n'
  printf '  "tool": "install.sh",\n'
  printf '  "run_id": "%s",\n' "$STAMP"
  printf '  "installed_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "source": "%s",\n' "$(json_escape "$SOURCE_ROOT")"
  printf '  "target": "%s",\n' "$(json_escape "$TARGET_ROOT")"
  printf '  "harnesses": [%s],\n' "$harness_json"
  printf '  "backup_root": "%s",\n' "$(json_escape "$backup_json")"
  printf '  "files": ['
  if [ ${#J_FILES[@]} -gt 0 ]; then
    printf '\n'
    first=1
    for frag in "${J_FILES[@]}"; do
      if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
      printf '    %s' "$frag"
    done
    printf '\n  '
  fi
  printf '],\n'
  printf '  "entries": ['
  if [ ${#J_ENTRIES[@]} -gt 0 ]; then
    printf '\n'
    first=1
    for frag in "${J_ENTRIES[@]}"; do
      if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
      printf '    %s' "$frag"
    done
    printf '\n  '
  fi
  printf '],\n'
  printf '  "uninstall": [\n'
  printf '    "1. entries[].path: 删掉 <!-- BEGIN agentrule:entry v1 --> 到 <!-- END agentrule:entry v1 --> 之间的内容（含两行标记）",\n'
  printf '    "2. files[] 里 action=create 的 path: 直接删",\n'
  printf '    "3. files[] 里 action=overwrite 的 path: 用同一条目的 backup 覆盖回去",\n'
  printf '    "4. files[] 里 action=unchanged 的 path: 装之前就有，不要动",\n'
  printf '    "5. 删掉状态目录 %s"\n' "$(json_escape "$STATE_DIR")"
  printf '  ]\n'
  printf '}\n'
} > "$MANIFEST"

if [ ${#LOG_LINES[@]} -gt 0 ]; then
  printf '%s\n' "${LOG_LINES[@]}" > "$STATE_DIR/apply.log"
else
  : > "$STATE_DIR/apply.log"
fi

say '[done]'
say "  写入 $WRITTEN 个文件"
if [ "$BACKUP_COUNT" -gt 0 ]; then
  say "  备份 $BACKUP_COUNT 个文件 -> $BACKUP_ROOT"
else
  say '  没有文件需要备份（没有覆盖任何已有内容）'
fi
say "  manifest -> $MANIFEST"
say ''
SIZE_BAD=0
for h in $SELECTED; do
  if ! test_entry_size "$h" "$(probe_entry "$h")"; then SIZE_BAD=1; fi
done
if [ "$SIZE_BAD" = 1 ]; then show_truncation_fix; fi
say ''
say '验收命令（现在就能跑，应输出 bad 0）:'
say "  bash \"$SCRIPT_DIR/install.sh\" --verify --harness $OPT_HARNESS --target \"$TARGET_ROOT\""
say ''
say '下一步（给 agent）:'
first_h="${SELECTED%% *}"
say "  1. 打开入口文件确认标记块在（搜 agentrule:entry v1）: $(probe_entry "$first_h")"
say '  2. 重启 harness 让入口文件生效；当前会话不变。'
if [ "$BACKUP_COUNT" -gt 0 ]; then
  say "  3. 回滚: 把 $BACKUP_ROOT 里的文件按相对路径拷回去。"
else
  say '  3. 回滚: 本次没有覆盖任何已有内容，删掉新建的 AgentRule/ 即可。'
fi
exit 0

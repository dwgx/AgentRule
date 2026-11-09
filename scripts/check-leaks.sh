#!/usr/bin/env bash
# check-leaks.sh — 发布前脱敏门（只报告，不改文件）
#
# 用法:
#   bash check-leaks.sh                 扫默认根（脚本所在目录）
#   bash check-leaks.sh --root DIR      指定扫描根
#   bash check-leaks.sh --local FILE    指定本机规则文件
#   bash check-leaks.sh --no-local      明确接受只跑 base 规则（不去找 leaks.local）
#   bash check-leaks.sh --rules         打印每类的 grep 命令（维护用）
#   bash check-leaks.sh --verbose       额外打印逐规则命中数
#   bash check-leaks.sh -h
#
# 退出码: 0 = 完整扫描且 TOTAL 0（干净）; 1 = 有命中;
#         2 = 扫描失败或不完整（目录/规则文件不存在、用法错、0 个文本文件、
#             grep 出错、未找到 leaks.local 且未给 --no-local）
#
# 输出: 明细在前（每类最多 3 条，格式 `文件:行号 [类别]`，不打印行内容），
#       然后 8 类各一行 `类名: N 行`，末行 `TOTAL: N`。
#       计数单位是命中行数；同一行命中同类多条规则算 1 行，跨类可重复计。
#
# 规则两层:
#   base  = 本文件里的通用规则（家目录 / 内网 IP / 凭据形状），任何仓库都适用
#   local = --local 指定的规则文件（默认 脚本目录/leaks.local，再试 扫描根/leaks.local）
#           放本机身份：用户名 / 盘符根 / 主机名 / 私有仓名。不进公开仓库。
# 没有 local 文件时默认 exit 2（扫描不完整，5 类没跑）；显式 --no-local 才只跑 base。
#
# 脚本自身与 leaks.local 被排除：规则表必须逐字包含被禁字符串。
set -u

# 规则格式: category@@label@@tier@@flags@@pattern[@@notpat]
#   category 8 类之一: username home-path d-project abs-drive intranet-ip hostname private-repo credential
#   tier     HARD = 确定是泄漏; REVIEW = 词形歧义需人判
#   flags    i = 忽略大小写, w = 整词
#   notpat   可选: 命中行里再匹配到它的丢掉（排占位符用）
CATS=(username home-path d-project abs-drive intranet-ip hostname private-repo credential)

BASE_RULES=(
  'home-path@@home-abs@@HARD@@i@@(^|[^A-Za-z0-9])[A-Za-z]:[\\/]+Users[\\/]@@[\\/]Users[\\/](你的名字|<[^>]*>|me|username|user|you|name|xxx|example|\.\.\.)([\\/]|[[:space:]"`)`]|$)'
  'home-path@@home-nocolon@@HARD@@i@@(^|[^A-Za-z0-9:])[A-Za-z][\\/]Users[\\/]@@[\\/]Users[\\/](你的名字|<[^>]*>|me|username|user|you|name|xxx|example|\.\.\.)([\\/]|[[:space:]"`)`]|$)'
  'intranet-ip@@ip-192-168@@HARD@@@@192\.168\.'
  'intranet-ip@@ip-10@@HARD@@@@(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  'intranet-ip@@ip-172@@HARD@@@@(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
  'credential@@token-openai@@HARD@@@@\bsk-[A-Za-z0-9]{8,}'
  'credential@@token-github@@HARD@@@@gh[pousr]_[A-Za-z0-9]{20,}'
  'credential@@token-github-pat@@HARD@@@@github_pat_[A-Za-z0-9_]{20,}'
  'credential@@token-aws@@HARD@@@@AKIA[0-9A-Z]{16}'
  'credential@@pem-begin@@HARD@@@@-----BEGIN'
  'credential@@token-slack@@HARD@@@@xox[baprs]-[A-Za-z0-9-]{8,}'
  'credential@@jwt@@HARD@@@@eyJ[A-Za-z0-9_-]{10,}'
)

SELF_BASE="$(basename "$0")"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT=""
LOCAL=""
SHOW_RULES=0
VERBOSE=0
NO_LOCAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    [ $# -ge 2 ] || { echo "--root 需要参数" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --root=*)  ROOT="${1#*=}"; shift ;;
    --local)   [ $# -ge 2 ] || { echo "--local 需要参数" >&2; exit 2; }; LOCAL="$2"; shift 2 ;;
    --local=*) LOCAL="${1#*=}"; shift ;;
    --rules)   SHOW_RULES=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --no-local) NO_LOCAL=1; shift ;;
    -h|--help) awk 'NR==1{next} /^set -u$/{exit} {print}' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  # 默认根: 装配后的仓库根 > 装配暂存 > 脚本目录
  if [ -d "$SELF_DIR/../install" ] || [ -d "$SELF_DIR/../protocol" ]; then
    ROOT="$SELF_DIR/.."
  elif [ -d "$SELF_DIR/stage" ]; then
    ROOT="$SELF_DIR/stage"
  else
    ROOT="$SELF_DIR"
  fi
fi
[ -d "$ROOT" ] || { echo "目录不存在: $ROOT" >&2; exit 2; }
ROOT_ABS="$(cd "$ROOT" && pwd)"

if [ -z "$LOCAL" ]; then
  for cand in "$SELF_DIR/leaks.local" "$ROOT_ABS/leaks.local"; do
    [ -f "$cand" ] && { LOCAL="$cand"; break; }
  done
fi
[ -n "$LOCAL" ] && [ ! -f "$LOCAL" ] && { echo "规则文件不存在: $LOCAL" >&2; exit 2; }

RULES=(); SRC=()
for r in "${BASE_RULES[@]}"; do RULES+=("$r"); SRC+=("base"); done
if [ -n "$LOCAL" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *@@*@@*@@*@@*) RULES+=("$line"); SRC+=("local") ;;
      *) echo "坏规则（要 category@@label@@tier@@flags@@pattern）: $line" >&2; exit 2 ;; esac
  done < "$LOCAL"
fi

split_rule() {
  local rest="$1"; PARTS=()
  while [ "${rest#*@@}" != "$rest" ]; do PARTS+=("${rest%%@@*}"); rest="${rest#*@@}"; done
  PARTS+=("$rest")
}

if [ "$SHOW_RULES" = 1 ]; then
  for i in "${!RULES[@]}"; do
    split_rule "${RULES[$i]}"
    cat_="${PARTS[0]}"; label="${PARTS[1]}"; tier="${PARTS[2]}"
    flags="${PARTS[3]}"; pat="${PARTS[4]}"; notpat="${PARTS[5]:-}"
    f=""; case "$flags" in *i*) f="${f}i" ;; esac; case "$flags" in *w*) f="${f}w" ;; esac
    printf '# %s / %s  [%s] (%s)\n' "$cat_" "$label" "$tier" "${SRC[$i]}"
    if [ -n "$notpat" ]; then
      printf "grep -rn%sE '%s' . | grep -vE '%s' | wc -l\n" "$f" "$pat" "$notpat"
      printf "grep -rn%sE '%s' . | grep -vE '%s'\n\n" "$f" "$pat" "$notpat"
    else
      printf "grep -rc%sE '%s' . | awk -F: '{s+=\$2} END{print s+0}'\n" "$f" "$pat"
      printf "grep -rn%sE '%s' .\n\n" "$f" "$pat"
    fi
  done
  exit 0
fi

# 缺 local 规则 = 5 类没扫，不能给 PASS；只有显式 --no-local 才接受 base-only。
if [ -z "$LOCAL" ] && [ "$NO_LOCAL" -ne 1 ]; then
  echo "扫描不完整 (exit 2): 没找到 leaks.local —— username / d-project / abs-drive / hostname / private-repo 这 5 类不会跑，PASS 不算数。" >&2
  echo "给 --local <规则文件>，或显式 --no-local 接受 base-only 扫描。" >&2
  exit 2
fi

FILE_N=$(find "$ROOT_ABS" -type f ! -name "$SELF_BASE" ! -name 'leaks.local' | wc -l | tr -d ' ')
TEXT_LIST="$( cd "$ROOT_ABS" || exit 2; grep -rIl '' --exclude="$SELF_BASE" --exclude='leaks.local' . 2>/dev/null )"
TEXT_RC=$?
if [ "$TEXT_RC" -gt 1 ]; then
  echo "VERDICT: ERROR (exit 2) — 文本文件枚举失败：grep -l 退出 $TEXT_RC，根目录：$ROOT_ABS" >&2
  exit 2
fi
TEXT_N=$(printf '%s' "$TEXT_LIST" | grep -c '')

# 0 个文件 = 根目录选错了。这时打 PASS 是假绿：它只证明"没扫到东西"。
if [ "$TEXT_N" -eq 0 ]; then
  echo "VERDICT: ERROR (exit 2) — 扫到 0 个文本文件，根目录选错了：$ROOT_ABS" >&2
  echo "提示：在仓库根跑 'bash scripts/check-leaks.sh'，或显式给 --root <仓库根>。" >&2
  exit 2
fi

echo "# root  : $ROOT_ABS"
echo "# files : $FILE_N（文本 $TEXT_N；二进制/空文件由 grep -I 跳过；脚本自身与 leaks.local 排除）"
echo "# rules : ${#RULES[@]} 条（base ${#BASE_RULES[@]} + local $(( ${#RULES[@]} - ${#BASE_RULES[@]} ))）"
if [ -n "$LOCAL" ]; then echo "# local : $LOCAL"; elif [ "$NO_LOCAL" -eq 1 ]; then echo "# NOTE  : --no-local —— 只跑 base 规则；username / d-project / abs-drive / hostname / private-repo 这 5 类未启用"; fi

declare -A CAT_HITS CAT_KEYS RULE_HITS
for c in "${CATS[@]}"; do CAT_HITS[$c]=0; CAT_KEYS[$c]=""; done
TOTAL=0
SCAN_ERR=0
SCAN_ERR_LABELS=()

for i in "${!RULES[@]}"; do
  split_rule "${RULES[$i]}"
  cat_="${PARTS[0]}"; label="${PARTS[1]}"; flags="${PARTS[3]}"
  pat="${PARTS[4]}"; notpat="${PARTS[5]:-}"

  opts=(-rInE)
  case "$flags" in *i*) opts+=(-i) ;; esac
  case "$flags" in *w*) opts+=(-w) ;; esac

  out="$( cd "$ROOT_ABS" || exit 2; grep "${opts[@]}" --exclude="$SELF_BASE" --exclude='leaks.local' --exclude-dir=.git -e "$pat" . 2>/dev/null )"
  grc=$?
  if [ "$grc" -gt 1 ]; then
    SCAN_ERR=1
    SCAN_ERR_LABELS+=("$label(rc=$grc)")
  fi
  if [ -n "$notpat" ] && [ -n "$out" ]; then
    out="$(printf '%s\n' "$out" | grep -vE -e "$notpat" || true)"
  fi

  if [ -z "$out" ]; then
    h=0
  else
    h=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    CAT_KEYS[$cat_]="${CAT_KEYS[$cat_]}$(printf '%s\n' "$out" | cut -d: -f1,2)"$'\n'
  fi
  RULE_HITS[$label]=$h
  CAT_HITS[$cat_]=$(( ${CAT_HITS[$cat_]} + h ))
done

# 每类取不重复行数；TOTAL = 这 8 个数之和（与下面打印的 8 行一致）
declare -A CAT_N
TOTAL=0
for c in "${CATS[@]}"; do
  CAT_N[$c]=$(printf '%s' "${CAT_KEYS[$c]}" | sort -u | grep -c '' )
  TOTAL=$((TOTAL + CAT_N[$c]))
done

# ---- 明细（每类最多 3 条；只打 文件:行号 [类别]，不打行内容，避免二次泄漏）----
for c in "${CATS[@]}"; do
  [ "${CAT_HITS[$c]}" -gt 0 ] || continue
  n=${CAT_N[$c]}
  echo ""
  echo "## $c: $n 行"
  printf '%s' "${CAT_KEYS[$c]}" | sort -u | awk -v c="$c" 'NF && NR<=3 {print "  " $0 " [" c "]"}'
  if [ "$n" -gt 3 ]; then echo "  ... 另有 $(( n - 3 )) 行"; fi
done

# grep 出错时命中数不完整：不能报 0，也不能把不完整的 1 当结论。
if [ "$SCAN_ERR" -eq 1 ]; then
  echo "" >&2
  echo "VERDICT: ERROR (exit 2) — 扫描未完成：${#SCAN_ERR_LABELS[@]} 条规则 grep 失败（${SCAN_ERR_LABELS[*]:-}），上面的计数不可信" >&2
  exit 2
fi

if [ "$VERBOSE" = 1 ]; then
  echo ""
  echo "# 逐规则命中:"
  for i in "${!RULES[@]}"; do
    split_rule "${RULES[$i]}"
    printf '#   %-14s %-22s %s\n' "${PARTS[0]}" "${PARTS[1]}" "${RULE_HITS[${PARTS[1]}]:-0}"
  done
fi

echo ""
for c in "${CATS[@]}"; do
  printf '%s: %s 行\n' "$c" "${CAT_N[$c]}"
done
printf 'TOTAL: %s\n' "$TOTAL"

[ "$TOTAL" -eq 0 ] && exit 0
exit 1

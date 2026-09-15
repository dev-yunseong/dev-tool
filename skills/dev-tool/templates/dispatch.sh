#!/usr/bin/env bash
#
# dispatch.sh - docker 와 같은 `<command> <subcommand>` 문법으로 프로젝트
# 개발 명령어를 실행합니다.
#
# 이 파일은 dev-tool 스킬이 배포하는 공용 runtime 입니다. 프로젝트마다
# 달라지는 것은 .dev/commands/<command>.sh 와 .dev/config.sh 뿐이므로,
# 이 파일은 프로젝트에서 수정하지 말고 스킬에서 통째로 갱신하십시오.
#
# command 파일 하나가 command 하나입니다. 파일은 세 가지를 정의합니다.
#
#   dev_describe          command 한 줄 설명을 출력
#   dev_verbs             dev_verb <이름> <인자> <설명> 을 subcommand 마다 호출
#   dev_run <sub> [args]  실제 실행
#
# dispatcher 가 목록과 문서를 만들 때 command 파일을 source 하므로, 파일의
# 최상위에서는 함수와 변수 정의만 하고 부수 효과를 내면 안 됩니다.

set -euo pipefail

[ -n "${DEV_ROOT:-}" ] || {
  printf 'error: DEV_ROOT is empty. Run the project'"'"'s ./dev launcher instead of this file.\n' >&2
  exit 1
}

COMMAND_DIR="$DEV_ROOT/.dev/commands"
DOC_FILE="$DEV_ROOT/DEV_TOOL.md"
DOC_START='<!-- dev:commands:start -->'
DOC_END='<!-- dev:commands:end -->'

# 프로젝트가 이름과 한 줄 소개를 바꾸고 싶을 때만 .dev/config.sh 를 둡니다.
DEV_NAME='./dev'
DEV_TAGLINE='프로젝트 개발 명령어'
# shellcheck source=/dev/null
[ -f "$DEV_ROOT/.dev/config.sh" ] && source "$DEV_ROOT/.dev/config.sh"

BUILTINS='help docs'

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- command 파일이 쓰는 helper -----------------------------------------------
#
# 묻고 저장하는 일은 command 마다 다시 짜면 매번 틀립니다. 특히 비대화형에서
# 멈춰버리는 것과 secret 을 화면에 찍는 것, 두 가지가 반복해서 납니다.
# 그래서 dispatcher 가 네 개를 제공합니다.

# 사람에게 물어볼 수 있는 상황인지. stdout 이 pipe 로 넘어가도 물어볼 수 있게
# stdin 대신 /dev/tty 를 봅니다.
dev_interactive() {
  # [ -r /dev/tty ] 로는 안 됩니다. terminal 에 붙어 있지 않은 process 에서도
  # /dev/tty 는 파일로 존재해서 검사를 통과하고, 실제로 열 때 가서야
  # "No such device or address" 로 실패합니다. 그래서 직접 열어봅니다.
  { : < /dev/tty; } 2>/dev/null || return 1
  { : > /dev/tty; } 2>/dev/null || return 1
  return 0
}

# dev_ask <변수이름> <물음> [기본값]
# 답을 그 이름의 변수에 넣습니다: dev_ask name '이름' 'game'; echo "$name"
#
# stdout 으로 돌려주지 않는 이유가 있습니다. name=$(dev_ask ...) 로 쓰면
# subshell 이 하나 생겨서, 그 안에서 die 를 불러도 바깥 script 는 멈추지
# 않고 빈 값을 들고 그냥 갑니다.
dev_ask() {
  [ $# -ge 2 ] || die "dev_ask takes a variable name and a question"
  local name=$1 question=$2 fallback=${3:-} answer

  dev_assert_variable_name "$name"

  if ! dev_interactive; then
    [ -n "$fallback" ] || die "'$question' 을 물어봐야 하는데 terminal 이 없습니다. 값을 인자로 주고 다시 실행하십시오."
    printf -v "$name" '%s' "$fallback"
    return 0
  fi

  if [ -n "$fallback" ]; then
    printf '%s [%s]: ' "$question" "$fallback" > /dev/tty
  else
    printf '%s: ' "$question" > /dev/tty
  fi

  IFS= read -r answer < /dev/tty || answer=''
  [ -n "$answer" ] || answer=$fallback
  printf -v "$name" '%s' "$answer"
}

# dev_ask_secret <변수이름> <물음>
# 입력을 화면에 찍지 않고, 그 이름의 변수에 넣습니다. 받은 값은 절대 다시
# 출력하지 마십시오.
dev_ask_secret() {
  [ $# -eq 2 ] || die "dev_ask_secret takes a variable name and a question"
  local name=$1 question=$2 answer

  dev_assert_variable_name "$name"
  dev_interactive || die "'$question' 은 secret 이라 terminal 에서만 받을 수 있습니다."

  printf '%s: ' "$question" > /dev/tty
  IFS= read -rs answer < /dev/tty || answer=''
  printf '\n' > /dev/tty
  printf -v "$name" '%s' "$answer"
}

dev_assert_variable_name() {
  case $1 in
    [A-Za-z_]*) ;;
    *) die "not a variable name: $1" ;;
  esac
  case $1 in
    *[!A-Za-z0-9_]*) die "not a variable name: $1" ;;
  esac
}

# dev_confirm <물음>
# yes 면 0, 아니면 1. 비대화형에서는 묻지 않고 1 을 돌려주므로, 위험한 일은
# 확인 없이 진행되지 않습니다.
dev_confirm() {
  local question=$1 answer

  dev_interactive || return 1

  printf '%s [y/N]: ' "$question" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=''
  case $answer in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# dev_config_set <파일> <키> <값>
# KEY=값 형태의 파일에 한 줄을 씁니다. 키가 이미 있으면 그 줄을 바꾸고, 없으면
# 뒤에 붙입니다. 파일을 새로 만들 때는 0600 으로 만듭니다. 기존 파일은
# 내용만 덮어써서 권한을 그대로 둡니다.
dev_config_set() {
  [ $# -eq 3 ] || die "dev_config_set takes 3 arguments: file, key, value"
  local file=$1 key=$2 value=$3

  [ -f "$file" ] || {
    umask 077
    : > "$file"
  }

  local temporary
  temporary=$(mktemp)
  DEV_CONFIG_VALUE=$value awk -v key="$key" '
    BEGIN { value = ENVIRON["DEV_CONFIG_VALUE"]; written = 0 }
    substr($0, 1, length(key) + 1) == key "=" {
      if (!written) { print key "=" value; written = 1 }
      next
    }
    { print }
    END { if (!written) print key "=" value }
  ' "$file" > "$temporary"

  cat "$temporary" > "$file"
  rm -f "$temporary"
}

# dev_config_get <파일> <키>
# 값을 stdout 으로. 키가 없으면 아무것도 내지 않고 1 을 돌려줍니다.
dev_config_get() {
  [ $# -eq 2 ] || die "dev_config_get takes 2 arguments: file, key"
  local file=$1 key=$2 value

  [ -f "$file" ] || return 1

  value=$(awk -v key="$key" '
    substr($0, 1, length(key) + 1) == key "=" { print substr($0, length(key) + 2) }
  ' "$file" | tail -n 1)

  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

# --- command 파일 ------------------------------------------------------------

list_commands() {
  local file
  for file in "$COMMAND_DIR"/*.sh; do
    [ -e "$file" ] || continue
    basename "$file" .sh
  done
}

# 수집한 subcommand. load_command 이 매번 비우고 다시 채웁니다.
VERB_NAMES=()
VERB_ARGS=()
VERB_TEXTS=()

dev_verb() {
  [ $# -eq 3 ] || die "dev_verb takes 3 arguments: name, arguments, description"
  VERB_NAMES+=("$1")
  VERB_ARGS+=("$2")
  VERB_TEXTS+=("$3")
}

load_command() {
  local command=$1 file="$COMMAND_DIR/$1.sh"
  [ -f "$file" ] || die "unknown command: $command. Run: $DEV_NAME help"

  VERB_NAMES=(); VERB_ARGS=(); VERB_TEXTS=()
  unset -f dev_describe dev_verbs dev_run 2>/dev/null || true

  # shellcheck source=/dev/null
  source "$file"

  declare -F dev_run >/dev/null || die "$file defines no dev_run function"
  declare -F dev_verbs >/dev/null && dev_verbs
  return 0
}

describe_command() {
  # 목록을 만드는 중이므로 깨진 파일 하나가 전체 목록을 막지 않도록 subshell
  # 에서 읽고, 설명이 없으면 빈 줄로 둡니다.
  ( load_command "$1" >/dev/null 2>&1 || exit 0
    declare -F dev_describe >/dev/null && dev_describe ) 2>/dev/null || true
}

# --- help --------------------------------------------------------------------

print_root_help() {
  printf '%s - %s\n\n' "$DEV_NAME" "$DEV_TAGLINE"
  printf '사용법:\n  %s <command> <subcommand> [options]\n\n' "$DEV_NAME"

  local command found=0
  printf 'command:\n'
  while read -r command; do
    [ -n "$command" ] || continue
    found=1
    printf '  %-12s %s\n' "$command" "$(describe_command "$command")"
  done < <(list_commands)
  [ "$found" -eq 1 ] || printf '  (없음. .dev/commands/ 에 command 파일을 추가하십시오.)\n'

  printf '  %-12s %s\n' 'help' '이 도움말'
  printf '  %-12s %s\n' 'docs' 'DEV_TOOL.md 의 명령어 표를 다시 만듭니다'
  printf '\n%s <command> 만 치면 그 command 의 subcommand 목록이 나옵니다.\n' "$DEV_NAME"
}

print_command_help() {
  local command=$1
  load_command "$command"

  local description
  description=$(declare -F dev_describe >/dev/null && dev_describe || true)
  printf '%s %s - %s\n\n' "$DEV_NAME" "$command" "$description"
  printf 'subcommand:\n'

  local i
  for i in "${!VERB_NAMES[@]}"; do
    printf '  %-12s %-14s %s\n' "${VERB_NAMES[$i]}" "${VERB_ARGS[$i]}" "${VERB_TEXTS[$i]}"
  done
  [ "${#VERB_NAMES[@]}" -gt 0 ] || printf '  (이 command 는 subcommand 를 알려주지 않습니다.)\n'
}

# --- docs --------------------------------------------------------------------

render_command_table() {
  local command i
  while read -r command; do
    [ -n "$command" ] || continue
    load_command "$command"
    printf '\n### `%s %s` — %s\n\n' "$DEV_NAME" "$command" \
      "$(declare -F dev_describe >/dev/null && dev_describe || true)"
    printf '| 명령어 | 하는 일 |\n| --- | --- |\n'
    for i in "${!VERB_NAMES[@]}"; do
      local usage="$DEV_NAME $command ${VERB_NAMES[$i]}"
      [ -n "${VERB_ARGS[$i]}" ] && usage="$usage ${VERB_ARGS[$i]}"
      printf '| `%s` | %s |\n' "$usage" "${VERB_TEXTS[$i]}"
    done
  done < <(list_commands)
}

cmd_docs() {
  [ -f "$DOC_FILE" ] || die "$DOC_FILE not found. Write it first; docs only refreshes the table."
  grep -qF "$DOC_START" "$DOC_FILE" || die "$DOC_FILE has no $DOC_START marker"
  grep -qF "$DOC_END" "$DOC_FILE" || die "$DOC_FILE has no $DOC_END marker"

  local table temporary
  table=$(render_command_table)
  temporary=$(mktemp)
  awk -v block="$table" -v start="$DOC_START" -v stop="$DOC_END" '
    index($0, start) { print; printf "%s\n\n", block; skipping = 1; next }
    index($0, stop)  { skipping = 0 }
    !skipping        { print }
  ' "$DOC_FILE" > "$temporary"
  mv "$temporary" "$DOC_FILE"
  printf 'updated the command table in %s\n' "$DOC_FILE" >&2
}

# --- main --------------------------------------------------------------------

assert_no_reserved_command_file() {
  local name
  for name in $BUILTINS; do
    [ -f "$COMMAND_DIR/$name.sh" ] && \
      die "$COMMAND_DIR/$name.sh 는 built-in 이름 $name 을 씁니다. 이 파일은 실행될 수 없으니 이름을 바꾸십시오."
  done
  return 0
}

main() {
  [ -d "$COMMAND_DIR" ] || die "$COMMAND_DIR not found. dev-tool 스킬로 다시 설치하십시오."
  assert_no_reserved_command_file

  local command=${1:-help}
  [ $# -gt 0 ] && shift

  case $command in
    help|-h|--help) print_root_help; return 0 ;;
    docs) cmd_docs; return 0 ;;
  esac

  [ -f "$COMMAND_DIR/$command.sh" ] || {
    printf 'error: unknown command: %s\n\n' "$command" >&2
    print_root_help >&2
    exit 1
  }

  local verb=${1:-help}
  [ $# -gt 0 ] && shift

  if [ "$verb" = help ] || [ "$verb" = -h ] || [ "$verb" = --help ]; then
    print_command_help "$command"
    return 0
  fi

  load_command "$command"

  if [ "${#VERB_NAMES[@]}" -gt 0 ]; then
    local known=0 name
    for name in "${VERB_NAMES[@]}"; do
      [ "$name" = "$verb" ] && known=1
    done
    [ "$known" -eq 1 ] || {
      printf 'error: %s has no subcommand %s\n\n' "$command" "$verb" >&2
      print_command_help "$command" >&2
      exit 1
    }
  fi

  dev_run "$verb" "$@"
}

main "$@"

#!/usr/bin/env bash
# Profiles are literal assignments, never shell scripts. Load them only into
# the child process so profile keys cannot change dispatcher state.

dev_describe() {
  echo '환경 변수를 프로필별로 저장하고 실행할 때 선택합니다'
}

dev_verbs() {
  dev_verb create '<profile>' '빈 환경 변수 프로필을 만듭니다'
  dev_verb set '<profile> <KEY> [--stdin]' '값을 숨겨 입력받아 저장합니다. --stdin 은 표준 입력 한 줄을 읽습니다'
  dev_verb list '' '저장된 프로필 이름을 보여줍니다'
  dev_verb show '<profile>' '변수 이름만 보여주고 모든 값은 숨깁니다'
  dev_verb run '<profile> -- <command> [args...]' '선택한 프로필의 환경 변수로 command 를 실행합니다'
}

dev_run() {
  local verb=$1
  shift
  case $verb in
    create) environment_create "$@" ;;
    set) environment_set "$@" ;;
    list) environment_list "$@" ;;
    show) environment_show "$@" ;;
    run) environment_run "$@" ;;
    *) die "unhandled subcommand: $verb" ;;
  esac
}

environment_file() {
  case $1 in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9_-]*)
      die '프로필 이름은 영문 또는 숫자로 시작하고 영문, 숫자, _ - 만 씁니다.' ;;
  esac
  printf '%s/.dev/environments/%s.env\n' "$DEV_ROOT" "$1"
}

environment_assert_private() {
  local file=$1
  dev_require git
  [ ! -L "$DEV_ROOT/.dev/environments" ] && [ ! -L "$file" ] ||
    die '환경 변수 프로필 경로에는 symbolic link 를 사용할 수 없습니다.'
  git -C "$DEV_ROOT" check-ignore -q -- "$file" ||
    die '먼저 .dev/environments/ 를 프로젝트의 .gitignore 에 추가하십시오.'
  if git -C "$DEV_ROOT" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    die 'Git 이 추적하는 파일에는 환경 변수 프로필을 저장할 수 없습니다.'
  fi
}

environment_validate() {
  local file=$1
  [ -f "$file" ] || die '환경 변수 프로필이 없습니다. env create 로 먼저 만드십시오.'
  # Report only line numbers: even malformed lines may contain credentials.
  awk '
    index($0, sprintf("%c", 0)) || index($0, "\r") { bad = NR; exit }
    /^$/ || /^#/ { next }
    {
      separator = index($0, "=")
      key = substr($0, 1, separator - 1)
      if (!separator || key !~ /^[A-Za-z_][A-Za-z0-9_]*$/ || seen[key]++) {
        bad = NR; exit
      }
    }
    END {
      if (bad) {
        printf "error: 환경 변수 프로필 %d번째 줄이 잘못되었거나 변수 이름이 중복됩니다.\n", bad > "/dev/stderr"
        exit 1
      }
    }
  ' "$file"
}

environment_create() {
  [ $# -eq 1 ] || die '사용법: env create <profile>'
  local file
  file=$(environment_file "$1")
  environment_assert_private "$file"
  [ ! -e "$file" ] || die '이미 있는 프로필입니다.'
  ( umask 077
    mkdir -p -- "${file%/*}"
    set -o noclobber
    : > "$file"
  )
  printf '프로필 생성: %s\n' "$1"
}

environment_set() {
  [ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$3" = --stdin ]; } ||
    die '사용법: env set <profile> <KEY> [--stdin]'
  local file key=$2 environment_value=''
  file=$(environment_file "$1")
  environment_assert_private "$file"
  environment_validate "$file"
  dev_assert_variable_name "$key"

  if [ "${3:-}" = --stdin ]; then
    if IFS= read -r -d '' environment_value; then
      die '환경 변수 값에 null 문자를 사용할 수 없습니다.'
    fi
    [ -n "$environment_value" ] || die '표준 입력에 값 한 줄이 필요합니다.'
    environment_value=${environment_value%$'\n'}
  else
    dev_ask_secret environment_value "$key 값"
  fi
  case $environment_value in
    *$'\n'*|*$'\r'*) die '환경 변수 값은 한 줄만 입력하십시오.' ;;
  esac

  # Replace atomically with mode 0600, including profiles edited by hand.
  ( umask 077
    local temporary
    temporary=$(mktemp "${file%/*}/.profile.XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    DEV_ENVIRONMENT_VALUE=$environment_value awk -v key="$key" '
      substr($0, 1, length(key) + 1) == key "=" { next }
      { print }
      END { print key "=" ENVIRON["DEV_ENVIRONMENT_VALUE"] }
    ' "$file" > "$temporary"
    mv -f -- "$temporary" "$file"
  )
  printf '변수 저장: %s (%s)\n' "$key" "$1"
}

environment_list() {
  [ $# -eq 0 ] || die '사용법: env list'
  local file profile
  for file in "$DEV_ROOT/.dev/environments/"*.env; do
    [ -f "$file" ] || continue
    profile=${file##*/}
    profile=${profile%.env}
    environment_file "$profile" >/dev/null
    environment_assert_private "$file"
    printf '%s\n' "$profile"
  done
}

environment_show() {
  [ $# -eq 1 ] || die '사용법: env show <profile>'
  local file
  file=$(environment_file "$1")
  environment_assert_private "$file"
  environment_validate "$file"
  awk '/^$/ || /^#/ { next } { print substr($0, 1, index($0, "=") - 1) "=<hidden>" }' "$file"
}

environment_run() {
  [ $# -ge 3 ] && [ "$2" = -- ] || die '사용법: env run <profile> -- <command> [args...]'
  local file line
  local assignments=()
  file=$(environment_file "$1")
  shift 2
  environment_assert_private "$file"
  environment_validate "$file"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|\#*) continue ;; esac
    assignments+=("$line")
  done < "$file"
  # env parses assignments without evaluation and preserves argument boundaries.
  command env -- "${assignments[@]}" "$@"
}

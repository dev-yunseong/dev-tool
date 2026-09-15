#!/usr/bin/env bash
#
# One file, .dev/commands/<name>.sh, is one `./dev <name>` command. Copy this
# file, rename it, and fill it in.
#
# The dispatcher sources this file whenever it builds a listing or the
# documentation table, so define functions and variables only at the top
# level. Anything that acts here runs again on every `./dev help`.
#
# Available to a command file:
#   $DEV_ROOT   absolute path of the project root
#   $DEV_NAME   the entry point name shown to the person (default ./dev)
#   die "..."   print to stderr and exit 1
#
# To ask for a value, confirm, and persist it, use dev_ask, dev_ask_secret,
# dev_confirm, dev_config_set and dev_config_get. The full contract is in
# references/command-contract.md; example_configure below shows them together.
#
# A subcommand that runs more than two things in order can use dev_step,
# dev_steps_done, dev_require and dev_wait_for to announce each step and to
# name the step a failure is attributed to. example_prepare below shows all
# four together; the full contract, including the two attribution paths, is
# in references/command-contract.md.
#
# Text this file prints goes to the person running the command, so the
# descriptions and messages are written in their language, not in English.

dev_describe() {
  echo '한 줄 설명. ./dev help 와 DEV_TOOL.md 에 그대로 나옵니다.'
}

dev_verbs() {
  # dev_verb <name> <arguments> <description>
  # Pass an empty string as the second argument when the subcommand takes none.
  dev_verb up        '[--detach]' '무언가를 띄웁니다'
  dev_verb status     ''          '지금 상태를 보여줍니다'
  dev_verb down       ''          '내립니다'
  dev_verb configure  ''          '설정 값을 확인하고, 없으면 물어서 저장합니다'
  dev_verb prepare    ''          'git 상태를 확인하고 표시 파일을 만듭니다'
}

dev_run() {
  local verb=$1
  shift

  case $verb in
    up)        example_up "$@" ;;
    status)    example_status ;;
    down)      example_down ;;
    configure) example_configure ;;
    prepare)   example_prepare ;;
    *)         die "unhandled subcommand: $verb" ;;
  esac
}

example_up() {
  echo "up: $* (DEV_ROOT=$DEV_ROOT)"
}

example_status() {
  echo 'status'
}

example_down() {
  echo 'down'
}

example_configure() {
  # Shows dev_config_get, dev_ask, dev_confirm and dev_config_set together.
  # A real command replaces the file name and the key name with its own.
  local config_file="$DEV_ROOT/.dev/local.env" value

  # Look for a stored value first; do not ask again when one is already there.
  value=$(dev_config_get "$config_file" EXAMPLE_TOKEN) || {
    dev_ask value 'Example token' ''
  }

  dev_confirm "$config_file 에 저장할까요?" || die 'aborted'

  dev_config_set "$config_file" EXAMPLE_TOKEN "$value"

  # Report the key, not the value. A command copied from this file should not
  # learn to print what it just stored.
  echo "EXAMPLE_TOKEN 을 ${config_file#"$DEV_ROOT"/} 에 저장했습니다."
}

example_prepare() {
  # Shows dev_require, dev_step, dev_wait_for and dev_steps_done together.
  # This does not stand up a real service: it checks git is present, runs two
  # trivial steps in order, and waits for the file the second step created.
  # A real command follows the same shape for a container, a migration, or
  # anything else that runs more than two things in order.
  local stamp_file="$DEV_ROOT/.dev/example.stamp"

  dev_require mkdir 'coreutils 가 설치되어 있어야 합니다'

  # Nothing here assumes anything about the project. The template is copied
  # into repositories of every shape, so an example that only works inside a
  # git repository, or only with a container runtime running, fails the first
  # time someone tries it.
  dev_step '작업 디렉터리 확인'
  [ -d "$DEV_ROOT/.dev" ] || die ".dev 디렉터리가 없습니다."

  dev_step '표시 파일 생성'
  : > "$stamp_file"

  dev_wait_for '표시 파일 확인' 5 test -f "$stamp_file"

  dev_steps_done
  echo "prepare 완료: ${stamp_file#"$DEV_ROOT"/} 을 만들었습니다."
}

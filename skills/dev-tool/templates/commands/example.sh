#!/usr/bin/env bash
#
# .dev/commands/<이름>.sh 한 파일이 `./dev <이름>` 하나입니다.
# 이 파일을 복사해서 이름을 바꾸고 안을 채우십시오.
#
# dispatcher 가 목록과 문서를 만들 때 이 파일을 source 하므로, 최상위에서는
# 함수와 변수 정의만 하십시오. 여기서 무언가를 실행하면 `./dev help` 를 칠
# 때마다 그게 같이 돌아갑니다.
#
# 쓸 수 있는 것:
#   $DEV_ROOT   프로젝트 루트 절대 경로
#   $DEV_NAME   사용자에게 보여줄 진입점 이름 (기본 ./dev)
#   die "..."   메시지를 내고 1 로 끝냅니다
#
# 값을 묻고 확인받고 저장하는 데는 dev_ask, dev_ask_secret, dev_confirm,
# dev_config_set, dev_config_get 을 씁니다. 전체 계약은
# references/command-contract.md 를 보십시오. 아래 example_configure 가
# 이 넷을 쓰는 예시입니다.

dev_describe() {
  echo '한 줄 설명. ./dev help 와 DEV_TOOL.md 에 그대로 나옵니다.'
}

dev_verbs() {
  # dev_verb <이름> <인자 표기> <설명>
  # 인자가 없으면 두 번째를 빈 문자열로 둡니다.
  dev_verb up        '[--detach]' '무언가를 띄웁니다'
  dev_verb status     ''          '지금 상태를 보여줍니다'
  dev_verb down       ''          '내립니다'
  dev_verb configure  ''          '설정 값을 확인하고, 없으면 물어서 저장합니다'
}

dev_run() {
  local verb=$1
  shift

  case $verb in
    up)        example_up "$@" ;;
    status)    example_status ;;
    down)      example_down ;;
    configure) example_configure ;;
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
  # dev_ask / dev_ask_secret / dev_confirm / dev_config_set / dev_config_get
  # 를 함께 쓰는 예시입니다. 실제 command 에서는 파일 이름과 키 이름을
  # 그 command 에 맞게 바꾸십시오.
  local config_file="$DEV_ROOT/.dev/local.env" value

  # 먼저 이미 저장된 값이 있는지 봅니다. 있으면 다시 묻지 않습니다.
  value=$(dev_config_get "$config_file" EXAMPLE_TOKEN) || {
    dev_ask value 'Example token' ''
  }

  dev_confirm "$config_file 에 저장할까요?" || die 'aborted'

  dev_config_set "$config_file" EXAMPLE_TOKEN "$value"
  echo "configured: EXAMPLE_TOKEN=$value"
}

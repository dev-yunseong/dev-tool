# dev-tool

dev-tool 은 프로젝트에 `./dev` 명령줄 진입점을 깔아 주는 agent skill 이다.

저장소마다 개발용 script 가 쌓인다. agent 는 어느 script 를 어떤 flag 로 부르는지 알지만, 저장소 주인은 그걸 외우고 있지 않다. `.agents/skills/test-env/scripts/testenv.sh up --yes --with game,lobby` 는 agent 에게 시킬 때만 굴러가는 명령이다. dev-tool 은 그 script 들을 docker 와 같은 문법 하나로 묶는다.

```sh
./dev db clone
./dev server up
```

## 하는 일

- **Dispatch** — `./dev <command> <subcommand> [options]`. `./dev` 는 command 목록, `./dev <command>` 는 그 command 의 subcommand 목록을 낸다. 없는 subcommand 는 목록을 보여주고 1 로 끝난다.
- **Plugin** — `.dev/commands/<이름>.sh` 파일 하나가 command 하나다. 함수 세 개 (`dev_describe`, `dev_verbs`, `dev_run`) 를 정의하면 끝이고, dispatcher 는 건드리지 않는다.
- **Document** — `./dev docs` 가 `DEV_TOOL.md` 의 명령어 표를 command 파일에서 다시 만든다. 설명이 한 곳에만 있으니 문서가 코드와 어긋나지 않는다.
- **Ask and store** — 묻고 파일에 저장하는 helper 를 dispatcher 가 준다. terminal 이 없으면 멈추지 않고 실패하고, secret 은 화면에 찍지 않는다.

## 설치

로컬 checkout 에서:

```sh
npx skills add . --skill dev-tool
```

GitHub 에서:

```sh
npx skills add dev-yunseong/dev-tool --skill dev-tool
```

## 사용

```text
이 저장소의 개발 script 들을 ./dev 로 묶어줘.
```

skill 이 프로젝트에 까는 것:

| 경로 | 무엇 |
| --- | --- |
| `dev` | 진입점. 프로젝트 루트를 찾아 dispatcher 에 넘긴다. |
| `.dev/dispatch.sh` | 공용 dispatcher. 프로젝트에서 고치지 않고 통째로 갱신한다. |
| `.dev/config.sh` | 이름과 한 줄 소개 (선택). |
| `.dev/commands/*.sh` | 그 프로젝트의 command. |
| `DEV_TOOL.md` | 한글 사용 설명. 명령어 표는 `./dev docs` 가 만든다. |

## command 파일

```bash
dev_describe() {
  echo '로컬 test database'
}

dev_verbs() {
  dev_verb clone '[--yes]' '공유 database 를 로컬 container 로 가져온다'
  dev_verb psql  ''        '로컬 clone 에 psql session 을 연다'
}

dev_run() {
  local verb=$1
  shift
  case $verb in
    clone) "$DEV_ROOT/scripts/db-clone.sh" "$@" ;;
    psql)  "$DEV_ROOT/scripts/db-psql.sh" ;;
    *)     die "unhandled subcommand: $verb" ;;
  esac
}
```

dispatcher 가 목록과 문서를 만들 때 이 파일을 source 하므로, 최상위에서는 함수 정의만 한다. 실행은 전부 `dev_run` 안에서 한다. 전체 contract 는 `skills/dev-tool/references/command-contract.md` 에 있다.

## 요구 사항

- bash 와 awk. 그 외 의존성은 없다.

## 주의할 점

- `.dev/dispatch.sh` 는 프로젝트에서 고치지 않는다. 고칠 것은 이 저장소의 template 이고, 프로젝트에는 파일을 통째로 덮어써서 전달한다.
- `DEV_TOOL.md` 의 marker 사이 표는 손으로 고치지 않는다. `dev_describe` 와 `dev_verb` 를 고치고 `./dev docs` 를 다시 돌린다.
- `help` 와 `docs` 는 dispatcher 가 쓰는 이름이다. 그 이름의 command 파일이 있으면 dispatcher 가 시작할 때 거부한다.

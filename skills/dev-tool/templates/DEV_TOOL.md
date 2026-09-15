# 개발 명령어

<!-- 이 문서는 dev-tool 스킬이 만든 템플릿입니다. 아래 안내를 이 프로젝트에
     맞게 고치고, 명령어 표는 ./dev docs 로 다시 만드십시오. -->

이 저장소의 개발 작업은 루트의 `./dev` 하나로 합니다. docker 와 같은
`./dev <command> <subcommand>` 문법입니다.

```bash
./dev
```

command 목록이 나옵니다. `./dev <command>` 는 그 command 의 subcommand 목록을
보여줍니다.

## 빠른 시작

<!-- 이 프로젝트에서 처음 환경을 만들 때 치는 명령어를 순서대로 적으십시오. -->

```bash
./dev
```

## 준비물

<!-- Docker, 설정 파일, submodule 초기화처럼 명령어가 돌기 전에 있어야 하는
     것들을 적으십시오. -->

## 명령어

아래 표는 `./dev docs` 가 `.dev/commands/` 를 읽어서 다시 만듭니다. 손으로
고치지 마십시오. 설명을 바꾸려면 command 파일의 `dev_describe` 와 `dev_verb`
줄을 고치고 `./dev docs` 를 다시 실행하십시오.

<!-- dev:commands:start -->
<!-- dev:commands:end -->

## 명령어 추가하기

1. `.dev/commands/<이름>.sh` 를 만듭니다. 기존 파일 하나를 복사하는 게 빠릅니다.
2. `dev_describe`, `dev_verbs`, `dev_run` 세 함수를 정의합니다.
3. `chmod +x` 는 필요 없습니다. dispatcher 가 source 합니다.
4. `./dev docs` 로 이 문서의 표를 갱신합니다.

command 파일은 목록을 만들 때마다 source 되므로, 최상위에서 무언가를 실행하면
안 됩니다. 실행은 전부 `dev_run` 안에서 하십시오.

## 구조

| 경로 | 무엇 |
| --- | --- |
| `dev` | 진입점. 프로젝트 루트를 찾아 dispatcher 에 넘깁니다. |
| `.dev/dispatch.sh` | 공용 dispatcher. dev-tool 스킬이 배포하며 여기서 고치지 않습니다. |
| `.dev/config.sh` | 이름과 한 줄 소개 (선택). |
| `.dev/commands/*.sh` | 이 프로젝트의 명령어. |

## 문제가 생기면

<!-- 자주 깨지는 지점과 그때 칠 명령어를 적으십시오. -->

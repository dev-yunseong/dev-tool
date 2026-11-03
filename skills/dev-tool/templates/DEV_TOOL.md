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

## 환경 변수 profile

<!-- env command 를 설치한 프로젝트에서만 이 절을 남기십시오. 설치할 때
     첫 profile 생성 전에 .dev/environments/ 를 .gitignore 에 추가하고
     git check-ignore .dev/environments/local.env 로 확인하십시오. -->

```bash
./dev env create local
./dev env set local DATABASE_URL
./dev env list
./dev env show local
./dev env run local -- ./dev server up
```

`set` 은 입력한 값이 보이지 않는 prompt 를 엽니다. 값을 명령 인자로
넘기지 마십시오. 자동화에서는 값을 출력하는 도구를
`./dev env set local DATABASE_URL --stdin` 에 연결하면 한 줄을 읽습니다.
`list` 는 profile 이름만 보여주고, `show` 는 모든 값을 `KEY=<hidden>` 으로
표시합니다.

profile 이름은 `[A-Za-z0-9][A-Za-z0-9_-]*` 형식입니다. 파일은
`.dev/environments/<profile>.env` 에 mode `0600` 으로 생성하며 Git 에서
제외되고 추적되지 않아야 합니다. `KEY=value` 를 한 줄씩 저장하며 빈 줄과
`#` 으로 시작하는 주석을 허용합니다. 값에 있는 공백과 `=` 는 그대로
유지합니다. 따옴표, 변수 치환, `export`, shell 실행 문법은 해석하지
않습니다. 잘못된 줄이나 중복 key 가 있으면 값을 출력하지 않고 실행 전에
실패합니다.

실행할 때 profile 을 명시해야 합니다. 기본 profile 은 자동으로 선택하지
않습니다. `run` 은 실행한 process 에서만 같은 이름의 환경 변수를 덮어쓰며,
profile 에 없는 환경 변수는 기존 값을 유지합니다. container 안에 필요한
환경 변수는 사용하는 도구가 container 로 전달하도록 별도로 설정하십시오.

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
| `.dev/environments/<profile>.env` | 로컬 환경 변수 profile (env command 설치 시, Git 제외). |

## 문제가 생기면

<!-- 자주 깨지는 지점과 그때 칠 명령어를 적으십시오. -->

# dev-tool

dev-tool 은 프로젝트에 `./dev` 명령줄 진입점을 깔아 주는 agent skill 입니다.

저장소마다 개발용 script 가 쌓입니다. agent 는 어느 script 를 어떤 flag 로 부르는지 알지만, 저장소 주인은 그걸 외우고 있지 않습니다. `.agents/skills/test-env/scripts/testenv.sh up --yes --with game,lobby` 는 agent 에게 시킬 때만 굴러가는 명령입니다.

dev-tool 은 그 script 들을 docker 와 같은 문법 하나로 묶고, 순서대로 엮어 자동화하고, 테스트 환경이 없는 프로젝트에는 없는 부분을 만들어 넣습니다.

```sh
./dev db clone
./dev server up
```

## 하는 일

- **Dispatch** — `./dev <command> <subcommand> [options]`. `./dev` 는 command 목록을, `./dev <command>` 는 그 command 의 subcommand 목록을 냅니다. 없는 subcommand 는 목록을 보여주고 1 로 끝납니다.
- **Plugin** — `.dev/commands/<이름>.sh` 파일 하나가 command 하나입니다. 함수 세 개 (`dev_describe`, `dev_verbs`, `dev_run`) 를 정의하면 끝이고, dispatcher 는 건드리지 않습니다.
- **Document** — `./dev docs` 가 `DEV_TOOL.md` 의 명령어 표를 command 파일에서 다시 만듭니다. 설명이 한 곳에만 있으니 문서가 코드와 어긋나지 않습니다.
- **Ask and store** — 묻고 파일에 저장하는 helper 를 dispatcher 가 줍니다. terminal 이 없으면 멈추지 않고 실패하고, secret 은 화면에 찍지 않습니다.
- **Branch** — component 여러 개의 branch 를 한 표로 보고 한 번에 맞춥니다. component 마다 다른 branch 를 지정할 수 있고, 조합을 이름 붙여 저장합니다.
- **Complete** — bash 와 zsh 에서 TAB 으로 command, subcommand, flag 가 완성됩니다.
- **Automate** — 여러 단계를 순서대로 돌리고, 실패하면 어느 단계에서 깨졌는지 말해 줍니다. 준비될 때까지 기다리는 것과 없는 도구를 미리 잡는 것도 dispatcher 가 줍니다.
- **Test environment** — 저장소에 이미 있는 compose 파일, migration, script 를 찾아 `up` / `down` / `status` / `logs` / `reset` 한 벌로 묶습니다. 없는 부분은 저장소가 보여 주는 것에 맞춰 만들어 넣습니다.

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
| `dev` | 진입점. 프로젝트 루트를 찾아 dispatcher 에 넘깁니다. |
| `.dev/dispatch.sh` | 공용 dispatcher. 프로젝트에서 고치지 않고 통째로 갱신합니다. |
| `.dev/config.sh` | 이름과 한 줄 소개 (선택). |
| `.dev/commands/*.sh` | 그 프로젝트의 command. |
| `.dev/completion.bash` | bash 와 zsh 용 TAB completion (선택). |
| `.dev/branches/<이름>` | `branch save` 가 남기는 component 별 branch 조합. |
| `DEV_TOOL.md` | 한글 사용 설명. 명령어 표는 `./dev docs` 가 만듭니다. |

## command 파일

```bash
dev_describe() {
  echo '로컬 test database'
}

dev_verbs() {
  dev_verb clone '[--yes]' '공유 database 를 로컬 container 로 가져옵니다'
  dev_verb psql  ''        '로컬 clone 에 psql session 을 엽니다'
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

dispatcher 가 목록과 문서를 만들 때 이 파일을 source 하므로, 최상위에서는 함수 정의만 하십시오. 실행은 전부 `dev_run` 안에서 합니다. 전체 contract 는 `skills/dev-tool/references/command-contract.md` 에 있습니다.

## 여러 component 의 branch

기능 하나가 submodule 이나 하위 저장소 여러 개에 걸쳐 있으면, 어느 component 가 어느 branch 에 있는지 흩어져서 안 보입니다. `branch` command 가 그걸 한 표로 보여주고 한 번에 맞춥니다.

```sh
./dev branch show
./dev branch use feature/10 lobby=main
./dev branch use game=feature/12
```

이름을 댄 component 는 그 branch 로 갑니다. 기본 branch 를 같이 주면 나머지도 따라가고, 안 주면 나머지는 그대로 둡니다.

| 입력 | 결과 |
| --- | --- |
| `./dev branch use feature/10` | 전부 `feature/10`, 없는 곳은 fallback (기본 `main`) |
| `./dev branch use feature/10 lobby=main` | 위와 같되 `lobby` 만 `main` |
| `./dev branch use game=feature/12` | `game` 만 이동, 나머지는 손대지 않습니다 |

세 번째가 핵심입니다. 인자를 단순하게 읽으면 `game` 만 지정했는데 나머지가 전부 `main` 으로 끌려갑니다. 시키지 않은 일이므로 하지 않습니다.

명시한 `component=branch` 의 branch 가 없으면 fallback 하지 않고 멈춥니다. 특정 branch 를 집어 요청했는데 조용히 다른 데로 보내는 것이 멈추는 것보다 나쁩니다. fallback 은 기본 branch 를 따라가는 component 에만 걸립니다.

origin 에만 있는 branch 는 tracking branch 로 만듭니다. component 목록은 `.dev/config.sh` 의 `DEV_COMPONENTS` 배열에서, 없으면 `.gitmodules` 의 submodule 경로에서 찾습니다.

### 조합 저장

```sh
./dev branch save my-feature
./dev branch list
./dev branch load my-feature
```

`.dev/branches/<이름>` 에 `component=branch` 한 줄씩 적힙니다. detached HEAD 인 component 는 적을 branch 이름이 없으므로 알리고 건너뜁니다. `load` 는 그 파일에 적힌 component 만 옮기고 나머지는 그대로 둡니다.

조합 파일에는 개인 작업 branch 이름이 들어가므로, `branch` command 를 설치할 때 `.dev/branches/` 를 그 프로젝트의 `.gitignore` 에 넣으십시오. 확장자가 없는 이름이라 `*.env` 같은 기존 규칙에는 걸리지 않습니다.

### 지키는 것

**전부 정하고 나서 바꿉니다.** 1차에서는 아무것도 쓰지 않고 계획만 세우고, 2차에서 실제로 옮깁니다. 중간에 실패해서 일부만 옮겨진 상태가 제일 알아채기 어렵기 때문입니다. `--dry-run` 은 1차까지만 하고 멈춥니다.

**변경사항이 있으면 거부합니다.** 옮겨야 하는 component 에 commit 하지 않은 변경이 있으면 전체를 거부하고 목록을 보여줍니다. `git stash` 는 쓰지 않습니다 — stash 는 같은 저장소의 worktree 사이에서 공유되므로, 한쪽이 밀어 넣은 것을 다른 쪽이 pop 해 가면 남의 작업을 조용히 가져갑니다.

경로가 없거나 git 저장소가 아닌 component 는 막지 않고 건너뜁니다. 초기화하지 않은 submodule 하나 때문에 나머지를 못 옮기면 안 되기 때문입니다.

## Tab completion

```sh
source ~/dev/my-project/.dev/completion.bash
```

이 한 줄을 shell 시작 파일에 넣으면 `./dev` 뒤에 TAB 이 먹습니다. bash 와 zsh 둘 다 되고, zsh 용 `bashcompinit` 은 파일이 알아서 부릅니다.

command 이름, 그 command 의 subcommand 이름, 그 subcommand 의 flag 까지 완성됩니다. flag 는 `dev_verb` 의 인자 표기에서 뽑으므로 따로 적을 곳이 없습니다 — `'[--dry-run]'` 이라고 써 두면 그게 후보가 되고, `'(dry run)'` 이라고 쓰면 안 됩니다.

생성하거나 caching 하는 것이 없습니다. completion 이 매번 `./dev complete` 를 되묻기 때문에, `.dev/commands/` 에 파일을 추가하면 그 즉시 완성됩니다.

TAB 을 누르면 `./dev` 가 실행되고 `.dev/commands/` 의 파일을 전부 source 합니다. `./dev` 를 쓸 때 어차피 도는 코드라 이미 쓰는 프로젝트에서는 새로운 노출이 아니지만, 코드를 신뢰하지 않는 저장소에는 걸지 마십시오.

## 여러 단계 엮기

두 가지 이상을 순서대로 돌리는 command 는 wrapper 가 아니라 자동화이고, wrapper 에는 없는 의무가 생깁니다. dispatcher 가 그걸 helper 로 줍니다.

```
==> database container 를 띄웁니다
==> migration 을 적용합니다

실패한 단계: migration 을 적용합니다 (exit 1)
```

`dev_step` 은 단계를 알리고 실패가 어느 단계 것인지 기록합니다. `die` 를 거치든 명령이 그냥 0 아닌 값으로 끝나든 양쪽 다 잡힙니다. `dev_wait_for` 는 준비될 때까지 기다립니다 — container 를 띄우는 것과 database 가 연결을 받는 것은 다른 일이라, 다음 단계가 시작 명령의 반환만 믿으면 안 됩니다. `dev_require` 는 없는 도구를 첫 단계 전에 잡습니다.

단계를 쓰지 않는 command 는 아무 영향도 받지 않습니다. 출력이 한 줄도 달라지지 않습니다.

## 테스트 환경

저장소를 먼저 읽습니다. compose 파일, migration 디렉터리, `Makefile` target, `package.json` script, Gradle task, `scripts/` 아래의 것들이 곧 환경이고, command 는 그것들을 감싸고 순서를 잡습니다. 이미 잘 도는 compose 파일이 있는 프로젝트에 compose 파일을 하나 더 쓰지 않습니다.

비어 있는 자리는 만들어 넣습니다. 그게 wrapper 와 다른 점입니다. 다만 저장소가 실제로 보여 주는 것에서 만들지, 어떤 stack 일 거라는 추측으로 만들지 않습니다.

전체 절차는 `skills/dev-tool/references/test-environment.md` 에 있습니다.

## 요구 사항

- bash 와 awk. 그 외 의존성은 없습니다.

## 주의할 점

- `.dev/dispatch.sh` 는 프로젝트에서 고치지 않습니다. 고칠 것은 이 저장소의 template 이고, 프로젝트에는 파일을 통째로 덮어써서 전달합니다.
- `DEV_TOOL.md` 의 marker 사이 표는 손으로 고치지 않습니다. `dev_describe` 와 `dev_verb` 를 고치고 `./dev docs` 를 다시 돌리십시오.
- `help`, `docs`, `complete` 는 dispatcher 가 쓰는 이름입니다. 그 이름의 command 파일이 있으면 dispatcher 가 시작할 때 거부합니다.

# Standing Up a Test Environment

This is the pattern in full, for when a project has no working way to bring
up a local environment and the command set has to be written, not just
wrapped. It assumes `references/command-contract.md` — read that first for
`dev_describe`, `dev_verbs`, `dev_run`, and the sourcing rule. The four
runtime helpers used throughout — `dev_step`, `dev_steps_done`,
`dev_require`, `dev_wait_for` — are documented in full there too.

## Surveying the repository

Read before writing a single line. Every one of these, if present, is part
of the environment already and the command set wraps it rather than
replacing it:

- **Container orchestration** — `docker-compose.yml`, `compose.yaml`, or a
  `Dockerfile` with no compose file at all (the container has to be built
  and run by hand in that case).
- **Migration tooling** — a `migration/` or `migrations/` directory, a
  `flyway.conf` or `flyway.toml`, a Liquibase changelog, or a framework's
  own migration runner (Django, Rails, a Spring Boot project's
  `db/migration` under `src/main/resources`).
- **Build tool targets that already do part of this** — a `Makefile` with
  targets like `db-up`, `test-env`, or `seed`; `package.json` `scripts`
  entries; Gradle tasks in `build.gradle` or `build.gradle.kts`.
  `./gradlew tasks` lists them when the file itself does not name them
  plainly.
- **Existing scripts** — anything under `scripts/` or `.agents/`, including
  another skill's script (a `test-env`-style skill some other project
  already has). Wrap it; never reimplement what it does.
- **Configuration templates** — `.env.example`, `.env.sample`, or a
  `config/` directory with placeholder values. These name every setting a
  command will have to derive or ask for.
- **`README` and `AGENTS.md`** — a "local development" or "getting started"
  section usually names the exact sequence a maintainer already trusts,
  even when no script encodes it yet.
- **CI workflow files** — `.github/workflows/*.yml` or equivalent. A step
  that stands up a database for tests in CI is frequently the same
  sequence a local environment needs, already proven to work in order.

## The command set

Five subcommands, named for the thing being acted on:

| Subcommand | Responsibility |
| --- | --- |
| `up` | Brings the environment to a running state: starts what needs starting, waits for it to be ready, applies migrations. Safe to run when it is already up. |
| `down` | Stops what `up` started. A `--purge` flag additionally removes volumes and networks, for a full clean slate. |
| `status` | Shows what is running, connection details, and migration state — without changing anything. |
| `logs` | Shows or tails the logs for one named component. |
| `reset` | Returns to a known clean state: `down --purge` followed by `up`. Requires confirmation, since it discards local data. |

A project that already has one of these under a different name gets a
subcommand that calls it. `./dev testenv up` calling `make db-up` under the
hood is the wrapping case; only the ordering and the readiness wait around
it are new.

## Worked skeleton

A project with a working `docker-compose.yml` (one service, `db`) and a
working `scripts/migrate.sh`, but nothing that starts the container, waits
for it, optionally clones a shared database into it, and migrates, in that
order. This is the file `up` and its siblings live in:

```bash
#!/usr/bin/env bash
#
# .dev/commands/testenv.sh - bring up a local test environment.
#
# This repository already has docker-compose.yml (a "db" service) and
# scripts/migrate.sh. Neither one waits for the other and nothing orders
# them, so this file adds the one missing piece: a single "up" that starts
# the container, waits for it to actually accept connections, optionally
# clones the shared dev database into it, then migrates.
#
# Top level defines only functions and plain variables. The dispatcher
# sources this file on every "./dev help" as well as on a real
# "./dev testenv ...".

TESTENV_CONFIG="$DEV_ROOT/.dev/testenv.env"
TESTENV_COMPOSE="$DEV_ROOT/docker-compose.yml"
TESTENV_CONNECTION='postgresql://postgres:postgres@localhost:5432/testenv'

dev_describe() {
  echo '로컬 테스트 환경 (Postgres container + clone + migration) 을 관리합니다'
}

dev_verbs() {
  dev_verb up     '[--yes]'   'container 를 올리고, 준비될 때까지 기다린 뒤 clone 과 migration 을 적용합니다'
  dev_verb down   '[--purge]' 'container 를 내립니다 (--purge 는 volume 도 지웁니다)'
  dev_verb status ''          'container 와 migration 상태를 보여줍니다'
  dev_verb logs   '<service>' '지정한 서비스의 로그를 보여줍니다'
  dev_verb reset  '[--yes]'   '내렸다가 다시 올려 알려진 초기 상태로 되돌립니다. --yes 없이는 거부합니다'
}

dev_run() {
  local verb=$1
  shift

  case $verb in
    up)     testenv_up "$@" ;;
    down)   testenv_down "$@" ;;
    status) testenv_status ;;
    logs)   testenv_logs "$@" ;;
    reset)  testenv_reset "$@" ;;
    *)      die "unhandled subcommand: $verb" ;;
  esac
}

# --- subcommand implementations ---------------------------------------------

testenv_up() {
  dev_require docker 'https://docs.docker.com/get-docker/ 에서 설치하십시오'
  dev_require psql 'apt-get install postgresql-client 로 설치하십시오'

  dev_step 'container 상태 확인'
  if docker compose -f "$TESTENV_COMPOSE" ps --status running --services 2>/dev/null | grep -qx db; then
    echo 'db container 가 이미 떠 있습니다. 새로 만들지 않습니다.'
  else
    docker compose -f "$TESTENV_COMPOSE" up -d db
  fi

  dev_step '데이터베이스 연결 대기'
  dev_wait_for 'db' 60 psql "$TESTENV_CONNECTION" -c '\q'

  local source_label
  source_label=$(dev_config_get "$TESTENV_CONFIG" SOURCE_LABEL) || source_label=''
  if [ -n "$source_label" ]; then
    if [ "${1:-}" = '--yes' ] || dev_confirm "$source_label 데이터베이스를 로컬로 clone 할까요?"; then
      testenv_clone "$source_label"
    else
      echo 'clone 을 건너뜁니다. 빈 schema 에 migration 만 적용합니다.'
    fi
  fi

  dev_step 'migration 적용'
  "$DEV_ROOT/scripts/migrate.sh"

  dev_steps_done

  echo "연결: $TESTENV_CONNECTION"
  echo "로그: $DEV_NAME testenv logs db"
}

# testenv_clone <source-label>
# The confirmation happens in testenv_up, before this is ever called, so this
# function itself never has to ask again.
testenv_clone() {
  local source_label=$1 source_url
  source_url=$(dev_config_get "$TESTENV_CONFIG" SOURCE_DATABASE_URL) || \
    die "$TESTENV_CONFIG 에 SOURCE_DATABASE_URL 이 없습니다"

  dev_step "$source_label 에서 clone"
  # source_url carries no password; a real command reads the credential
  # through its own driver and never echoes or logs it.
  pg_dump "$source_url" | psql "$TESTENV_CONNECTION"
}

testenv_down() {
  dev_require docker

  local purge_args=()
  [ "${1:-}" = '--purge' ] && purge_args=(-v)

  docker compose -f "$TESTENV_COMPOSE" down "${purge_args[@]}"
}

testenv_status() {
  dev_require docker
  docker compose -f "$TESTENV_COMPOSE" ps
}

testenv_logs() {
  local service=${1:-}
  [ -n "$service" ] || die "$DEV_NAME testenv logs <service> 처럼 서비스 이름을 주십시오"
  dev_require docker
  docker compose -f "$TESTENV_COMPOSE" logs -f "$service"
}

testenv_reset() {
  [ "${1:-}" = '--yes' ] || \
    die "$DEV_NAME testenv reset 은 로컬 데이터베이스를 지웁니다; 확인하려면 --yes 를 주십시오"

  testenv_down --purge
  testenv_up --yes
}
```

What this shows, end to end:

- `dev_require` runs before `dev_step` announces anything — both
  prerequisites are checked before the sequence starts.
- `dev_step` labels each stage; `dev_wait_for` sits between starting the
  container and doing anything that needs a live connection to it;
  `dev_steps_done` runs once, after the last step, before the closing
  report.
- The clone is confirmed by name (`$source_label 데이터베이스를 로컬로
  clone 할까요?`) before it runs, and `--yes` is the only way to skip that
  prompt — the same flag also lets `testenv_reset` drive `testenv_up`
  without hanging on a prompt no one is there to answer.
- Nothing is printed at the top level; every side effect is inside
  `dev_run`'s call tree, and `TESTENV_CONFIG`, `TESTENV_COMPOSE`, and
  `TESTENV_CONNECTION` are plain top-level assignments, not `declare` —
  see "The `declare`-at-top-level trap" in `references/command-contract.md`
  for why that distinction matters here.
- The closing report names the connection string and where the logs are,
  and prints no credential — `TESTENV_CONNECTION` here carries a fixed
  local password by construction, not one read out of the clone.

## Failure modes to plan for

- **The container runtime is not running.** `dev_require docker` catches
  the binary being absent; it does not catch the daemon being stopped. Let
  the `docker compose` call itself fail and surface its own message rather
  than guessing at one — do not fall back to a host-installed database
  client. A host with no client tools installed has no fallback to fall
  back to.
- **A port is already taken.** Name the port and, where the tool can show
  it, what is holding it, rather than a bare "address already in use". Point
  at the fix: a `LOCAL_DB_PORT`-style setting in the project's own config
  file, not a suggestion to stop whatever else is using the port.
- **A migration fails partway through.** Report the failing migration's
  identifier verbatim — its version number or file name — and stop. This is
  almost always a real defect in the migration itself, not a local
  environment problem, so it needs to be surfaced exactly, not worked
  around or retried.
- **A component was never initialized.** A submodule not checked out, a
  config file that was never derived, a database the clone step never ran
  for. Name which component and what is missing, and point at the specific
  step that creates it — `env-patch`, `db-init`, whatever the project calls
  it — rather than a generic "not configured".

## What not to do

- Do not invent a stack the repository does not show. A project with no
  Compose file and no Dockerfile does not get one manufactured from a
  guess at what the services probably are; report what is missing and stop.
- Do not write a second Compose file, migration runner, or config format
  next to a working one. If `docker-compose.yml` already exists, wrap it;
  a parallel `docker-compose.testenv.yml` invented alongside it is a second
  source of truth that will drift from the first.
- Do not make the destructive path the default. `reset` requires `--yes`
  for exactly this reason: the safe subcommand (`status`, `logs`) is what
  runs with no flags, and the one that discards local state never is.

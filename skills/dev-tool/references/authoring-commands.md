# Authoring ./dev Commands

## Designing the commands

Read the project's existing scripts, its skills, its README, and its
AGENTS.md before writing a single command file. Wrap what already exists;
do not reimplement it inside a command file.

Group commands by the thing being acted on — the database, the game server,
the deploy — not by the script that happens to implement it today. A
project with `scripts/db-clone.sh` and `scripts/db-migrate.sh` gets one
command file, `.dev/commands/db.sh`, with subcommands `clone` and
`migrate`, not two command files named after the scripts.

When the underlying tool already has a name for something — a Docker
Compose service, a Flyway command, an npm script — keep that name as the
subcommand. Someone who already knows the underlying tool should be able to
guess the `./dev` subcommand, so moving between the two never requires
relearning vocabulary.

### Deriving configuration instead of asking for it

A project's `./dev` should be able to set itself up. A command that needs
configuration — an API key, a target host, a module name — first tries to
derive it from files already on the machine: an existing `.env`, a config
file the underlying tool already reads, a value `dev_config_get` already
recorded from an earlier run. It asks the person, with `dev_ask` or
`dev_ask_secret`, only for what it genuinely cannot derive.

Asking a person to retype a credential that already exists on disk is a
defect, not a feature. See [command file contract](command-contract.md) for the full
contract of `dev_ask`, `dev_ask_secret`, `dev_confirm`, `dev_config_set`,
and `dev_config_get`.

## Composing steps

A command file that calls one script and returns is a wrapper. A command
that runs more than two things in order is automation, not a wrapper, and
it takes on obligations a wrapper does not:

- **Every step announced.** Call `dev_step <label>` before each one, so a
  person watching output that scrolls past sees what is currently running,
  not only what already failed.
- **The failing step named.** `dev_step` sets the step a failure is
  attributed to, and this holds whether the failure goes through `die` or
  the step's own command simply exits non-zero — the dispatcher runs under
  `set -Eeuo pipefail` with an `ERR` trap that reports the current step
  either way. Call `dev_steps_done` once the last step succeeds, so a later
  failure inside the same `dev_run` is not blamed on a step that already
  finished.
- **Prerequisites checked before the first step, not discovered halfway
  through.** Call `dev_require <executable> [hint]` for every executable
  the sequence depends on before `dev_step` announces the first one. A
  sequence that dies on step four because `flyway` was never installed has
  already done three steps of work that now has to be cleaned up by hand.
- **A wait on readiness, not on a start command returning.** Starting a
  database container is not the same as the database accepting
  connections. A step that brings something up and a step that depends on
  it belong on either side of a `dev_wait_for <label> <seconds>
  <command...>` call, not back to back.

`dev_step`, `dev_steps_done`, `dev_require`, and `dev_wait_for` are
documented in full in [command file contract](command-contract.md); reference them from
a command file rather than restating what they do.

A command that does one thing — one script, one call — needs none of this.
Reach for `dev_step` and `dev_wait_for` only once a command file is
actually sequencing several things.

## Standing up a test environment

A project with no working way to bring up a local environment does not
stop this skill. [test environment guide](test-environment.md) has the full pattern —
the repository checklist, the command set, a worked skeleton command file,
and the failure modes to plan for. This section is the summary.

### Read the repository before writing anything

The environment already exists in pieces, scattered across the
repository. Look for: a Docker Compose file, a `Makefile` with targets
like `db-up` or `test-env`, `package.json` scripts, Gradle tasks, a
migration directory (Flyway, Liquibase, or a framework's own), and any
script under `scripts/` or `.agents/`. These pieces, in whatever order
they already imply, are the environment. The command set wraps and orders
them.

### Wrap what exists; write only what is missing

A project with a working Compose file gets a command that calls it, not a
second Compose file next to it. A project with nothing gets the missing
piece written for it — that is what makes this more than a wrapper — but
it is written from what the repository actually shows: its own compose
service names, its own migration tool, its own scripts. Never from a guess
about the stack.

### The command set

Aim for five subcommands, named for the thing being acted on, following
the grammar rule above: bring the environment up, tear it down, show its
status, show its logs, and reset it back to a known state. A project that
already has one of these under another name — `db-up`, `serve` — gets a
subcommand that calls it, not a competing reimplementation.

### Idempotency

Running the bring-up command twice must be safe and must not duplicate
state. This is usually a check before an action: is the container already
running, does the local database already exist, before creating either.
A subcommand that is not safe to run twice — it drops and recreates
unconditionally, say — must say so in its `dev_verb` description, not
leave the person to discover it by re-running.

There are two ways to be safe to re-run, and a command has to pick one on
purpose. Check before creating is the common one: skip the container that
is already running, keep the database that already exists. Always end at
the same state is the other: tear the local copy down and rebuild it every
time, which is what a command whose whole job is refreshing a clone from a
source has to do — skipping the copy would defeat it. Both are re-runnable.
The failure is the third case, where a second run neither skips nor
rebuilds and leaves duplicated or half-updated state behind. A command
that rebuilds every time says so in its `dev_verb` description, because
the person is about to lose whatever they changed in the local copy.

### Readiness and prerequisites

The same rules as "Composing steps" above apply here, and matter more: a
readiness wait with `dev_wait_for` between starting a container and
connecting to it, and `dev_require` for every executable the environment
needs, checked before the first step runs.

### What to print when it finishes

How to reach the thing it started — a connection string, a URL, a port —
and where its logs land, so the next command a person reaches for is
`logs`, not a search for where output went.

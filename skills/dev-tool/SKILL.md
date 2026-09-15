---
name: dev-tool
description: >
  Installs or refreshes a ./dev command line entry point for a project: a
  docker-like `./dev <command> <subcommand> [options]` grammar that wraps
  existing scripts, composes them into ordered automation, and stands up a
  local test environment — writing the missing pieces when the project does
  not already have them — so the person who owns the repository can run
  development work by hand instead of by script path. Use it to make a
  project's development work runnable by hand, to set up a ./dev command
  line for a repository, to add a command to an existing ./dev, to build a
  local test environment for a project that has none, or to write or
  refresh DEV_TOOL.md. Triggers on $dev-tool.
metadata:
  short-description: Install a ./dev command line entry point for a project
---

# dev-tool

## Why

An agent working in a repository knows which script to run and which flags
to pass it. The person who owns the repository does not carry that
knowledge, and a script three directories deep behind a project-specific
flag is not something they can be expected to remember or guess. One entry
point with one predictable grammar — `./dev <command> <subcommand>
[options]` — fixes that: one thing to type, discoverable with `./dev` and
`./dev <command>` alone.

`DEV_TOOL.md`, the usage document at the project root, is generated from the
command files rather than hand-maintained, so it stays true to what `./dev`
actually does — the descriptions it prints come straight from
`dev_describe` and `dev_verb` in the command files, not from separately
written prose.

Wrapping one script behind one name is the base case, and two things go
past it. A command that runs more than one script in order is automation,
not a wrapper, and composing steps that way carries obligations a
single-script wrapper does not — see "Composing steps" below. And when a
project has no working way to stand up a local environment at all, the
skill does not stop at listing what is missing: it writes the missing
command from what the repository already shows — its compose files, its
migration directory, its existing scripts — the same way it wraps a script
that already exists. See "Standing up a test environment" below.

## When to use it

Use it when a command will be run repeatedly: a build, a local environment,
a data migration, a deploy step — anything the project owner or another
agent will reach for again. A command earns a place in `./dev` by being run
more than once.

Do not use it for a one-off command. Running something once by its full
script path is not a reason to wrap it.

## Installing into a project

1. Copy `templates/dev` to `<root>/dev` and `chmod +x` it.
2. Copy `templates/dispatch.sh` to `<root>/.dev/dispatch.sh`.
3. Copy `templates/completion.bash` to `<root>/.dev/completion.bash`. See
   "Tab completion" below for how a person installs it into their own
   shell.
4. Copy `templates/DEV_TOOL.md` to `<root>/DEV_TOOL.md` and rewrite its
   prose for this project. `DEV_TOOL.md` is user-facing and must be written
   in Korean, matching the template's own language.
5. Optionally copy `templates/config.sh` to `<root>/.dev/config.sh` when the
   project wants a display name or a one-line tagline other than the
   defaults (`./dev` and `프로젝트 개발 명령어`).
6. Write the command files under `<root>/.dev/commands/`. See "Designing
   the commands" below, and read `references/command-contract.md` for the
   full file contract before writing one.
7. Optionally copy `templates/commands/branch.sh` to
   `<root>/.dev/commands/branch.sh` when the project has more than one
   component whose branches move independently — submodules, or sibling
   repositories listed in `.dev/config.sh`. A single-repository project
   does not need it. See "The `branch` command" below. When you install
   it, add `.dev/branches/` to the project's `.gitignore`; see
   "`branch save` writes local files" below for why.
8. Run `./dev docs` to fill the command table in `DEV_TOOL.md`.

Do not edit anything under `templates/` while installing — copy from it.

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
defect, not a feature. See `references/command-contract.md` for the full
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
documented in full in `references/command-contract.md`; reference them from
a command file rather than restating what they do.

A command that does one thing — one script, one call — needs none of this.
Reach for `dev_step` and `dev_wait_for` only once a command file is
actually sequencing several things.

## Standing up a test environment

A project with no working way to bring up a local environment does not
stop this skill. `references/test-environment.md` has the full pattern —
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

## Safety

A test environment usually means real data and real credentials. State
this plainly rather than softening it:

- A command that copies data from a shared or production system must show
  which system, by name, and get explicit confirmation with `dev_confirm`
  before it acts. `dev_confirm` returns 1 without asking when there is no
  terminal, so an unattended run never takes that branch by default.
- A credential written to a file goes to a path the repository ignores,
  verified with `git check-ignore` before writing, at mode 0600 —
  `dev_config_set` already creates a new file that way.
- Never print a credential, a token, or a connection string that carries a
  password into a summary.
- Derive configuration from files already on the machine before asking a
  person to type a credential — see "Deriving configuration instead of
  asking for it" above.
- Cloned data stays local. Do not upload it.

## The `branch` command

`./dev branch` shows, moves, and remembers which branch each component of
a multi-component project sits on — submodules, or sibling repositories
the project lists in `.dev/config.sh`. A ready-made command file,
`templates/commands/branch.sh`, ships with the skill; copy it in rather
than writing an equivalent by hand.

Install it in a project with more than one component whose branches move
independently. A single-repository project does not need it.

### Component discovery

`branch` finds the component list in this order:

1. the `DEV_COMPONENTS` array in `.dev/config.sh`
2. the submodule paths in `.gitmodules`
3. the repository itself, if neither of the above is present

### `branch show`

Prints one row per component: its name, whether it has uncommitted
changes, and its current branch. A detached HEAD shows as the short
commit instead of a branch name. A path that is not a git repository
shows its change column as unknown rather than clean — a git repository
can be clean or dirty, but a directory that is not a repository at all is
neither, and marking it unknown keeps that apart from an actually clean
component at a glance.

### `branch use [branch] [component=branch ...] [--fallback <branch>] [--fetch] [--dry-run]`

Moves components onto branches. An argument with no `=` is the default
branch, applied to every component that was not named explicitly. An
argument of the form `component=branch` moves only that component, to
that branch. Both kinds may appear in the same invocation, and either
kind alone is a complete request — `branch use` requires only that at
least one of them is present.

The rule for which component moves, and where:

- `./dev branch use feature/10` — every component goes to `feature/10`,
  or to the fallback (default `main`) where `feature/10` does not exist
  for that component.
- `./dev branch use feature/10 lobby=main` — the same, except `lobby`
  goes to `main` instead of `feature/10`.
- `./dev branch use game=feature/12` — only `game` moves, to
  `feature/12`. No default branch was given, so nothing else is touched.

Naming a component moves that component. Naming a default branch as well
is what pulls the rest along. A run that names only one component must
not drag every other component onto the fallback behind the person's
back — that is what a simpler reading of the arguments would do, and it
is wrong.

An explicit `component=branch` that does not resolve — neither locally
nor on `origin` — blocks that component rather than falling back to
`main` or to `--fallback`. The person asked for a specific branch;
silently putting that component somewhere else would be worse than
stopping. The fallback applies only to components following the default
branch, never to an explicitly named one. A branch that exists only on
`origin` is checked out as a new tracking branch, for both the default
branch and an explicit `component=branch`.

- `--fallback <branch>` — branch to use instead of `main` when the
  default branch does not exist for a component that is following it.
- `--fetch` — runs `git fetch origin` in each component before planning.
  Without it, the command works from whatever was last fetched, so a
  branch pushed to `origin` after the last fetch will not be found.
- `--dry-run` — prints the plan and stops before touching anything.

### `branch save <name>`

Records each component's current branch into `.dev/branches/<name>`, one
line per component. A component on a detached HEAD is skipped, with a
notice printed, because there is no branch name to record — writing the
commit hash instead would make `branch load` check out a commit rather
than a branch. A missing path or a non-repository is skipped the same way
`branch use` skips one. If nothing was recorded — every component was
skipped — `branch save` refuses and removes the file rather than leaving
an empty one behind.

`<name>` is checked against `[A-Za-z0-9._-]`, and `.` and `..` are
rejected outright, so a name cannot escape `.dev/branches/`. `./dev
branch save ../escape` exits 1 and names the rule in its message.

#### `branch save` writes local files

Add `.dev/branches/` to the project's `.gitignore` when installing
`branch.sh`. A saved combination names the feature branches one person is
working on, which is theirs and not the project's, and it goes stale the
moment those branches are merged or deleted.

The rule has to be written explicitly. Saved combinations carry no file
extension, so a `.gitignore` that already covers `*.env` or similar
patterns does not catch them, and they would otherwise show up as
untracked files for every person who runs `branch save`. Check with
`git check-ignore -v .dev/branches/example` after adding the rule; it
should print the `.gitignore` line that matches.

### `branch load <name> [--fetch] [--dry-run]`

Moves each component named in `.dev/branches/<name>` to the branch that
file records for it. A component the file does not mention is left
alone — the same rule `branch use` follows for a component nobody named.
`--fetch` and `--dry-run` behave exactly as they do for `branch use`.

### `branch list`

Prints every saved combination's name, followed by each component and
the branch it recorded.

### Design points and why

- **Two passes.** The first pass decides everything and writes nothing;
  the second pass performs the checkouts. A run that failed halfway
  through would leave some components on the new branch and some on the
  old one — the state that is hardest to notice and hardest to recover
  from. `branch use` and `branch load` both build a plan and then apply
  it through the same second pass.
- **Never stashes.** A component that would have to move but has
  uncommitted changes blocks the whole operation: nothing is switched, the
  blocked components are listed, and the command exits 1. A dirty component
  already sitting on the target branch is left alone and blocks nothing,
  since no checkout would touch it. It never runs `git stash`. Stash is
  shared across worktrees of the same repository, so one session's stash
  can be popped by another session, silently taking someone else's work.
  The blocked-components message names the stash rule only when at least
  one component was blocked by uncommitted changes; a component blocked
  because its target branch does not exist gets a plain notice that
  nothing was changed, with no mention of stash — advice about the wrong
  problem sends the reader looking in the wrong place.
- **Missing or non-repository paths are skipped, not blocked.** An
  uninitialized submodule is common, and one uninitialized submodule must
  not stop the other components from moving. `branch save` applies the
  same skip.
- **A component with no resolvable target blocks the operation.** A
  component following the default branch blocks when neither that branch
  nor the fallback exists for it. An explicitly named `component=branch`
  blocks when that branch alone does not exist — it does not fall
  through to the fallback. Either way, the command refuses rather than
  leaving that component on an unrelated branch — the exact inconsistency
  `branch use` exists to prevent.
- **Never commits, resets, or touches submodule pointers on its own.**
  When `.gitmodules` is present, the command reports that the submodule
  pointers now differ and leaves committing them as a separate decision.

## Tab completion

`./dev complete` is a dispatcher built-in that prints names only, one per
line, with no descriptions — it exists for a shell completion script to
call, not for a person to type:

- `./dev complete` — every command file's name, plus `help` and `docs`.
- `./dev complete <command>` — that command's subcommand names.
- `./dev complete <command> <subcommand>` — the long flags found in that
  subcommand's `dev_verb` arguments string.

An unknown command or subcommand prints nothing and exits 0, because the
person is still typing; it is not an error. `complete` itself is never
offered as a completion candidate, and it does not appear in `./dev help`.

`templates/completion.bash` is the shell side, copied to
`<root>/.dev/completion.bash` during installation (see "Installing into a
project" above). A person installs it by sourcing that copy from their
shell startup file, pointing at the project:

```sh
source ~/dev/my-project/.dev/completion.bash
```

It registers for both `dev` and `./dev`, works in bash and in zsh (loading
zsh's `bashcompinit` itself), and asks the launcher the person actually
typed — `"${COMP_WORDS[0]}" complete ...` — so `./dev` in one project
directory answers for that project and a different one answers for its
own. Nothing is generated or cached: a command file added today is
completable immediately.

The one caveat worth telling a project owner: pressing TAB runs the
project's `./dev`, which sources every file in `.dev/commands/`. That is
the same code that already runs on any `./dev` invocation, so it is no new
exposure in a project they already work in — but it is a reason not to
install the completion script for a repository whose code they would not
otherwise run.

## Updating an existing installation

To bring a project's dispatcher up to date with a newer `dispatch.sh`,
replace `<root>/.dev/dispatch.sh` wholesale from `templates/dispatch.sh`.
Leave `<root>/.dev/commands/` alone — those files are project-specific and
an update to the dispatcher does not touch them.

## Adding one command to a project that already has `./dev`

1. Write `<root>/.dev/commands/<name>.sh`.
2. Run `./dev docs`.
3. Run `./dev <name>` and check the subcommand list renders as expected.

## Verification checklist

Run all of these before reporting the work done:

- `./dev` lists every command, each with its one-line description.
- `./dev <command>` lists that command's subcommands.
- `./dev <command> <unknown-subcommand>` exits non-zero and prints the
  subcommand list.
- `./dev docs` fills the command table between the markers in
  `DEV_TOOL.md`.
- Running `./dev docs` a second time in a row leaves `DEV_TOOL.md`
  unchanged — the table generation is idempotent.
- `./dev complete` lists every command file's name plus `help` and `docs`,
  and does not list `complete` itself.
- `./dev complete <command>` lists that command's subcommand names.
- `./dev complete <command> <subcommand>` lists the long flags parsed out
  of that subcommand's `dev_verb` arguments string.
- `./dev complete <unknown-command>` prints nothing and exits 0.
- After sourcing `.dev/completion.bash`, pressing TAB completes command
  names, subcommand names, and long flags, in both bash and zsh.

When `branch` is installed, also run:

- `./dev branch show` lists every component with its branch and whether
  it has uncommitted changes.
- `./dev branch use <branch> --dry-run` against a component with
  uncommitted changes prints that component as blocked and exits 1,
  without switching any component and without adding anything to `git
  stash list`.
- `./dev branch use <component>=<branch>` moves only `<component>` and
  leaves every other component on its current branch.
- `./dev branch use <branch> <component>=<other-branch>` moves
  `<component>` to `<other-branch>` and every other component to
  `<branch>`.
- `./dev branch save <name>` followed by `./dev branch use <some-other-
  branch>` and then `./dev branch load <name>` returns every recorded
  component to the branch `branch save` captured, and `./dev branch list`
  shows `<name>` with those components and branches.

## Rules

- Never edit `.dev/dispatch.sh` inside a project. It is a copy of
  `templates/dispatch.sh`; changes belong in the template and reach a
  project by replacing the file wholesale.
- Never hand-edit the command table in `DEV_TOOL.md` between the
  `<!-- dev:commands:start -->` and `<!-- dev:commands:end -->` markers.
  Change `dev_describe` or `dev_verb` in the command file and run
  `./dev docs` instead.
- Never put a secret or a credential in a command file or in
  `DEV_TOOL.md`.
- Before writing a credential to disk with `dev_config_set`, confirm the
  target file is gitignored (`git -C "$DEV_ROOT" check-ignore -q <file>`).
  A credential belongs only in a file the repository will never track.
- A command that touches shared or production state must ask for
  confirmation before acting. If it adds a flag that skips that
  confirmation, the command's `dev_describe` or the relevant `dev_verb`
  description must say so.
- A command that changes a working tree must refuse when the tree is
  dirty instead of stashing it, and must decide everything it is going to
  do before it changes anything. `branch use` is the model: it plans in a
  first pass, checks out in a second, and blocks on uncommitted changes
  instead of running `git stash`.

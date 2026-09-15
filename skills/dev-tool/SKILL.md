---
name: dev-tool
description: >
  Installs or refreshes a ./dev command line entry point for a project: a
  docker-like `./dev <command> <subcommand> [options]` grammar that wraps
  existing scripts so the person who owns the repository can run development
  work by hand instead of by script path. Use it to make a project's
  development work runnable by hand, to set up a ./dev command line for a
  repository, to add a command to an existing ./dev, or to write or refresh
  DEV_TOOL.md. Triggers on $dev-tool.
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
3. Copy `templates/DEV_TOOL.md` to `<root>/DEV_TOOL.md` and rewrite its
   prose for this project. `DEV_TOOL.md` is user-facing and must be written
   in Korean, matching the template's own language.
4. Optionally copy `templates/config.sh` to `<root>/.dev/config.sh` when the
   project wants a display name or a one-line tagline other than the
   defaults (`./dev` and `프로젝트 개발 명령어`).
5. Write the command files under `<root>/.dev/commands/`. See "Designing
   the commands" below, and read `references/command-contract.md` for the
   full file contract before writing one.
6. Optionally copy `templates/commands/branch.sh` to
   `<root>/.dev/commands/branch.sh` when the project has more than one
   component whose branches move independently — submodules, or sibling
   repositories listed in `.dev/config.sh`. A single-repository project
   does not need it. See "The `branch` command" below.
7. Run `./dev docs` to fill the command table in `DEV_TOOL.md`.

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

## The `branch` command

`./dev branch` shows and aligns which branch each component of a
multi-component project sits on — submodules, or sibling repositories the
project lists in `.dev/config.sh`. A ready-made command file,
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

### `branch use <branch> [--fallback <branch>] [--fetch] [--dry-run]`

Moves every component onto `<branch>` where that branch exists, and onto
the fallback (default `main`) where it does not. A branch that exists
only on `origin` is checked out as a new tracking branch.

- `--fallback <branch>` — branch to use instead of `main` when `<branch>`
  does not exist for a component.
- `--fetch` — runs `git fetch origin` in each component before planning.
  Without it, the command works from whatever was last fetched, so a
  branch pushed to `origin` after the last fetch will not be found.
- `--dry-run` — prints the plan and stops before touching anything.

### Design points and why

- **Two passes.** The first pass decides everything and writes nothing;
  the second pass performs the checkouts. A run that failed halfway
  through would leave some components on the new branch and some on the
  old one — the state that is hardest to notice and hardest to recover
  from.
- **Never stashes.** A component that would have to move but has
  uncommitted changes blocks the whole operation: nothing is switched, the
  blocked components are listed, and the command exits 1. A dirty component
  already sitting on the target branch is left alone and blocks nothing,
  since no checkout would touch it. It never runs `git stash`. Stash is
  shared across worktrees of the same repository, so one session's stash
  can be popped by another session, silently taking someone else's work.
- **Missing or non-repository paths are skipped, not blocked.** An
  uninitialized submodule is common, and one uninitialized submodule must
  not stop the other components from moving.
- **A component with neither branch blocks the operation.** If neither
  `<branch>` nor the fallback exists for a component, the command refuses
  rather than leaving that component on an unrelated branch — the exact
  inconsistency `branch use` exists to prevent.
- **Never commits, resets, or touches submodule pointers on its own.**
  When `.gitmodules` is present, the command reports that the submodule
  pointers now differ and leaves committing them as a separate decision.

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

When `branch` is installed, also run:

- `./dev branch show` lists every component with its branch and whether
  it has uncommitted changes.
- `./dev branch use <branch> --dry-run` against a component with
  uncommitted changes prints that component as blocked and exits 1,
  without switching any component and without adding anything to `git
  stash list`.

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

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
6. Run `./dev docs` to fill the command table in `DEV_TOOL.md`.

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

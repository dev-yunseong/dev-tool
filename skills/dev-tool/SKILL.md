---
name: dev-tool
description: >
  Installs or refreshes a ./dev command line entry point for a project: a
  docker-like command and subcommand grammar that wraps existing scripts,
  composes them into ordered automation, runs commands with named environment
  profiles, and stands up a
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

Use `./dev <command> <subcommand> [options]` for repeatable project tasks.
Generate the command table in `DEV_TOOL.md` from the command files with
`./dev docs`.

## References

- Read the [command file contract](references/command-contract.md) before
  writing or editing command files.
- Read [authoring commands](references/authoring-commands.md) when designing
  commands, composing steps, or deriving configuration.
- Use the [test environment guide](references/test-environment.md) when
  adding or repairing a local test environment.
- Read [bundled commands and completion](references/bundled-commands.md)
  when working on branch switching, environment profiles, or shell completion.

## Installing into a project

1. Copy `templates/dev` to `<root>/dev` and `chmod +x` it.
2. Copy `templates/dispatch.sh` to `<root>/.dev/dispatch.sh`.
3. Copy `templates/completion.bash` to `<root>/.dev/completion.bash`. See the
   [completion setup](references/bundled-commands.md#tab-completion).
4. Copy `templates/DEV_TOOL.md` to `<root>/DEV_TOOL.md` and rewrite its
   prose for this project. `DEV_TOOL.md` is user-facing and must be written
   in Korean, matching the template's own language.
5. Optionally copy `templates/config.sh` to `<root>/.dev/config.sh` when the
   project wants a display name or a one-line tagline other than the
   defaults (`./dev` and `프로젝트 개발 명령어`).
6. Write the command files under `<root>/.dev/commands/`. Follow the
   [command file contract](references/command-contract.md).
7. Optionally copy `templates/commands/branch.sh` to
   `<root>/.dev/commands/branch.sh` when the project has more than one
   component whose branches move independently — submodules, or sibling
   repositories listed in `.dev/config.sh`. A single-repository project
   does not need it. When installing it, add `.dev/branches/`
   to the project's `.gitignore`. See [branch setup](references/bundled-commands.md#the-branch-command).
8. Optionally copy `templates/commands/env.sh` to
   `<root>/.dev/commands/env.sh` when the project needs named local
   environment profiles. Before creating any profile, add
   `.dev/environments/` to the project's `.gitignore` and verify it with
   `git check-ignore .dev/environments/local.env`. See
   [environment profiles](references/bundled-commands.md#the-env-command).
   This command needs no dispatcher changes.
9. Run `./dev docs` to fill the command table in `DEV_TOOL.md`.

Do not edit anything under `templates/` while installing — copy from it.

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
  person to type a credential — see
  [configuration discovery](references/authoring-commands.md#deriving-configuration-instead-of-asking-for-it).
- Cloned data stays local. Do not upload it.

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

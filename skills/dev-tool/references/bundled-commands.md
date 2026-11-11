# Bundled Commands and Completion

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

## The `env` command

`templates/commands/env.sh` is an optional command file for named local
environment profiles. Copy it rather than implementing another loader.

```sh
./dev env create local
./dev env set local DATABASE_URL
./dev env list
./dev env show local
./dev env run local -- ./dev server up
```

- `create <profile>` creates `.dev/environments/<profile>.env` at mode
  `0600`. Profile names must match `[A-Za-z0-9][A-Za-z0-9_-]*`.
- `set <profile> <KEY>` asks for a single-line value with terminal echo
  disabled. `set <profile> <KEY> --stdin` reads one line from standard
  input for automation. Never pass a value as a command argument.
- `list` prints profile names only; `show <profile>` prints each key as
  `KEY=<hidden>`, masking every value.
- `run <profile> -- <command> [args...]` applies the selected profile only
  to the launched process. Profile values override inherited values with
  the same key; absent keys stay inherited. There is no implicit default
  or automatic profile selection.

Profile files must be gitignored and untracked. Add `.dev/environments/`
to the project's `.gitignore` before creating one. The format is literal
`KEY=value`, with blank lines and lines starting with `#` allowed. Values
are single-line; spaces and `=` remain literal. Never source these files:
there is no quote processing, interpolation, `export`, or shell evaluation.
An invalid file or duplicate key fails before execution without printing
values.

Document how the project's existing tool forwards environment variables
into containers when needed. Launching that tool with a profile does not
itself configure container environment forwarding. Keep the environment
profile section in `DEV_TOOL.md` only when this command is installed.

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
`<root>/.dev/completion.bash` during installation. A person installs it by sourcing that copy from their
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

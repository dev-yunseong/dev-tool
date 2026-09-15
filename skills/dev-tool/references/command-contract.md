# Command File Contract

This is the full contract for a `.dev/commands/<name>.sh` file. It is
precise enough to write a command file without reading `dispatch.sh`
itself. Read it before writing or editing any command file.

## One file, one command

`.dev/commands/<name>.sh` is one command. The file name, without the `.sh`
extension, is the command name — `.dev/commands/db.sh` gives `./dev db`.

`help`, `docs`, and `complete` are reserved by the dispatcher itself. A
command file may not take any of these three names. The dispatcher enforces
this before it does anything else: if `.dev/commands/help.sh`,
`.dev/commands/docs.sh`, or `.dev/commands/complete.sh` exists, every
`./dev` invocation exits 1 and names the offending file. Without that check
such a file would appear in the root listing and never run, because the
built-in handler claims the name first.

`complete` differs from the other two in one respect: it never appears in
`./dev help`'s root listing, because it is plumbing for a shell completion
script, not a command a person types by hand. `help` and `docs` are
commands a person does type, so `./dev help`'s root listing names both of
them explicitly. See "Tab completion: `./dev complete`" below for what
`complete` does.

## The three functions

A command file defines three functions, in this order by convention:

- `dev_describe` — echoes a single line: the command's one-line
  description. Shown next to the command name in `./dev`'s root listing and
  as the heading line for the command in `DEV_TOOL.md`.
- `dev_verbs` — calls `dev_verb <name> <arguments> <description>` once for
  each subcommand the command supports.
- `dev_run <subcommand> [args...]` — does the actual work. Required; the
  dispatcher refuses a command file that has no `dev_run`.

`dev_verbs` is technically optional — a command file without it still
loads — but write it every time. Without it the dispatcher has no list of
known subcommands, so it cannot reject an unrecognized one before calling
`dev_run`, and `./dev docs` renders that command's section with a header
and no rows, since there is nothing to fill the table with.

## `dev_verb`

```
dev_verb <name> <arguments> <description>
```

Exactly three arguments, every time — the dispatcher errors out of
`dev_verbs` if a call has more or fewer.

- `<name>` — the subcommand word, e.g. `up`, `clone`, `status`.
- `<arguments>` — how the subcommand's own arguments look in a usage line,
  e.g. `'[--detach]'` or `'<version>'`. Pass an empty string `''` when the
  subcommand takes none.
- `<description>` — one line, what the subcommand does. This is the text
  that ends up in both `./dev <command>`'s subcommand listing and the
  generated table in `DEV_TOOL.md` — there is no separate place to write
  subcommand documentation, so word it for the reader of `DEV_TOOL.md`, not
  just as an inline code comment.

## What the dispatcher provides

Inside a command file, at both the top level and inside its functions:

- `$DEV_ROOT` — the project root, as an absolute path.
- `$DEV_NAME` — the display name the project uses for its entry point,
  `./dev` unless the project's `.dev/config.sh` overrides it. Use this
  instead of hardcoding `./dev` in any message the command prints, so the
  message stays correct for a project that renamed its entry point.
- `die "message"` — prints `error: message` to stderr and exits with
  status 1. Use it for any fatal condition inside `dev_run`.

Nothing else from the dispatcher's own internals (its arrays, its other
functions) is part of the contract. Do not read or set them from a command
file.

## Asking, confirming, and persisting settings

Six more functions are available inside `dev_run`, alongside `die`. They
exist because a command file that asks a person for input, or writes a
setting to disk, tends to get non-interactive handling and secret handling
wrong in a slightly different way each time it is written from scratch — so
the dispatcher provides the six once, correctly.

### `dev_interactive`

Returns 0 when the process can actually open `/dev/tty` for both reading
and writing; returns 1 otherwise. It opens the device rather than testing
`[ -r /dev/tty ]`, because a process with no controlling terminal — a cron
job, a CI runner, a command piped from another program — still has
`/dev/tty` present as a file node, so `[ -r /dev/tty ]` passes, and only the
actual open call fails, with "No such device or address". `dev_ask`,
`dev_ask_secret`, and `dev_confirm` already call `dev_interactive`
internally; call it directly only when a command needs to branch on
interactivity for some other reason.

### `dev_ask <variable-name> <question> [default]`

```bash
dev_ask module 'Which module' 'game'
echo "$module"
```

Asks `<question>` on `/dev/tty` and stores the answer into the variable
named by `<variable-name>`. An empty answer at the prompt falls back to
`[default]` when one was given. When `dev_interactive` fails, `dev_ask`
uses `[default]` if one was given, or calls `die` if not — a
non-interactive run either proceeds with a sensible default or stops
cleanly, rather than hanging on a prompt no one can answer.

`dev_ask` stores into a variable instead of writing to stdout and returning
it through `$(...)`. This is a correctness requirement, not a style
choice. Written as `name=$(dev_ask ...)`, the call runs inside a command
substitution subshell; a `die` called from inside `dev_ask` in that
subshell exits only the subshell, so the caller keeps running with `name`
set to an empty string and an exit status of 0. Storing into a
caller-named variable keeps `die` fatal for the caller instead: a
non-interactive `dev_ask` with no default now exits the whole script with
status 1, and the line after it never runs. This was verified directly —
against the earlier stdout-returning version, a non-interactive `dev_ask`
printed its error and the script continued to the next line with exit
status 0; against the current version, the script exits 1 and the
following line never runs.

### `dev_ask_secret <variable-name> <question>`

```bash
dev_ask_secret api_key 'API key'
```

Same as `dev_ask` — same named-variable behavior and the same reason for
it — with terminal echo turned off while the answer is typed, and no
default; there is no argument for one. When `dev_interactive` fails,
`dev_ask_secret` always calls `die`. A secret can only be typed at a
terminal, never supplied as a fallback baked into a command file.

Never print a value that came from `dev_ask_secret`. Do not `echo` it, do
not put it in a `die` message, do not pass it to another program in a way
that program might log.

### `dev_confirm <question>`

```bash
dev_confirm 'Drop the local database and reclone it?' || exit 0
```

Returns 0 only when the person answers `y`, `Y`, `yes`, or `YES`; any other
answer, including an empty one, returns 1. When `dev_interactive` fails,
`dev_confirm` returns 1 without asking — an unattended run never takes the
confirmed branch by default. Gate a destructive action on `dev_confirm`
returning 0, never on it merely being callable.

### `dev_config_set <file> <key> <value>`

```bash
dev_config_set "$DEV_ROOT/.dev/local.env" API_KEY "$api_key"
```

Writes `KEY=value` into a `KEY=value` style file: replaces the existing
line for `<key>` when one is present, appends a new line when it is not.
When `<file>` does not exist yet, `dev_config_set` creates it under
`umask 077`, so it starts at mode 0600. When `<file>` already exists,
`dev_config_set` rewrites the file's contents in place through `cat`
rather than replacing it with `mv`, so the file's existing permissions and
ownership survive.

`<value>` passes to the underlying `awk` call through the environment, not
as program text, so it round-trips unchanged whatever it contains — `=`,
`&`, `/`, `?`, backslashes, spaces, non-ASCII characters all included.

### `dev_config_get <file> <key>`

```bash
existing_key=$(dev_config_get "$DEV_ROOT/.dev/local.env" API_KEY) || existing_key=''
```

Prints the value for `<key>` to stdout and returns 0. Returns 1 and prints
nothing when `<file>` does not exist or `<key>` is not in it. When
`<key>` appears more than once in the file, prints the value from the last
occurrence.

### Rules for these six

- Never print a value that came from `dev_ask_secret` — not in a message
  to the terminal, not in a `die` string, not in output a command writes
  to a log file.
- Never write a secret or a credential into a file the repository tracks.
  Before calling `dev_config_set` with a credential, check that the
  target file is gitignored: `git -C "$DEV_ROOT" check-ignore -q <file>`
  returns 0 when it is.
- `dev_ask` and `dev_config_get` are fine for values that are not secret —
  a module name, a target environment, a port number. Reach for
  `dev_ask_secret` specifically when the value is a credential.

### Worked example

Asks for a target environment, confirms before deploying, and persists
the choice for next time:

```bash
setup_target() {
  local target config_file="$DEV_ROOT/.dev/local.env"

  dev_ask target 'Target environment' 'staging'
  dev_confirm "Deploy to $target now?" || die 'aborted'
  dev_config_set "$config_file" DEV_TARGET "$target"

  "$DEV_ROOT/scripts/deploy.sh" "$target"
}
```

## The sourcing rule, and why it matters

The dispatcher sources a command file — `source "$file"` — every time it
needs that command's functions: to run a subcommand, to print the
command's subcommand list, to describe the command in the root listing, and
to render the command's section of the documentation table.

That means a command file's top level runs on every one of those
occasions, including a plain `./dev help` that never touches this command
at all — `describe_command` sources every command file in the project just
to collect each one's `dev_describe` line. A command file's top level must
therefore define only functions and variables. Anything that acts — a
network call, a file write, launching a process — belongs inside
`dev_run`, never at the top level and never inside `dev_describe` or
`dev_verbs`.

`describe_command`, used when building the root listing, sources the file
inside a subshell and discards errors, so a broken command file cannot take
down `./dev`'s own listing. `dev_run` itself is not protected that way: it
runs for real, in the dispatcher's own shell, exactly once, for the
subcommand the user asked for.

### The `declare`-at-top-level trap

The dispatcher sources a command file from inside its own `load_command`
function (`source "$file"`, called from `load_command`). That means a
command file's top level does not run in the dispatcher's outer shell — it
runs inside `load_command`. A `declare` at the file's top level therefore
creates a variable local to `load_command`, not a variable that survives
until `dev_run` is called: `load_command` returns, the declaration goes
with it, and by the time `dev_run` runs, the name is gone.

`.dev/commands/branch.sh` hit this directly. It first declared its
per-component state with `declare -A WANTED` at the file's top level, and
the first assignment into it, `WANTED[alpha]=...`, failed with `alpha:
unbound variable`. The array had lost its associative attribute along with
its scope, so `WANTED[alpha]=...` was parsed as an indexed array
subscript rather than an associative-array key, and under `set -u` the
bare word `alpha` was read as a variable reference — one that was never
set. The error names a value, not a variable, which is not self-explaining
on its own; the actual defect is the `declare` at the top level, not
anything wrong with `alpha`.

The fix was to move the `declare` inside the functions that use the
state — `local -A WANTED=()` inside `branch_use` and inside `branch_load` —
rather than at the file's top level. Bash's dynamic scoping then makes
each caller's locals visible to `branch_apply_plan`, which both `branch_use`
and `branch_load` call, without the state needing to be global.

The rule for any command file: never use `declare` at the file's top level
to create state you expect to survive past that one `source` call.
Declare it `local` inside the function that uses it, the way `branch_use`
and `branch_load` do, and rely on bash's dynamic scoping to make it
visible to any function that function calls. Use `declare -g` instead only
when the state genuinely must be global — visible across functions that do
not call each other. Either way, never leave the `declare` sitting at the
top level.

## How subcommand validation works

After the dispatcher sources a command file for a real invocation, it has a
list of every `dev_verb` name the file declared. If that list is
non-empty, the dispatcher checks the requested subcommand against it before
calling `dev_run`; an unrecognized subcommand prints the command's
subcommand list to stderr and exits 1 without ever calling `dev_run`. If
the file declared no `dev_verbs` at all, the dispatcher skips this check
entirely and passes whatever subcommand the user typed straight to
`dev_run` — another reason to always write `dev_verbs`, so a typo reaches
the user as a clean error rather than as whatever `dev_run`'s own `case`
statement does with an unmatched value.

Write `dev_run` as a `case` over the subcommand regardless, with a `*)`
branch that calls `die "unhandled subcommand: $verb"` — the dispatcher's
own validation covers the documented subcommands, but the `case` statement
is what actually handles them, and its `*)` branch is the backstop for
anything that reaches `dev_run` unvalidated.

## How the documentation table is built

`./dev docs` regenerates the table between the `<!-- dev:commands:start
-->` and `<!-- dev:commands:end -->` markers in `DEV_TOOL.md`, replacing
everything between them. It requires `DEV_TOOL.md` to exist and to already
contain both markers; it fails otherwise rather than creating the file or
inserting markers on its own.

For each command file, in the order `.dev/commands/*.sh` sorts, it sources
the file and emits one heading — the command name and its `dev_describe`
line — followed by a two-column Markdown table with one row per
`dev_verb` call: the full invocation (`$DEV_NAME <command> <name>
<arguments>`) in the left column, the subcommand's description in the
right column.

Nothing else in `DEV_TOOL.md` is touched. The prose above and below the
markers is written by hand once, when the project's `DEV_TOOL.md` is
created or revised, and `./dev docs` never changes it — only the block
between the markers is regenerated, and it is regenerated from scratch
every time, so running `./dev docs` twice in a row with no command files
changed must leave the file byte-for-byte the same.

## Tab completion: `./dev complete`

`./dev complete` is the interface a shell completion script uses —
`templates/completion.bash` calls it, and calls nothing else. It prints
names only, one per line, with no descriptions:

- `./dev complete` with no arguments prints every command file's name
  (from `.dev/commands/*.sh`), plus `help` and `docs`. `complete` is never
  among them.
- `./dev complete <command>` prints that command's `dev_verb` names, in the
  order `dev_verbs` declared them. A command file with no `dev_verbs` at
  all, or one that does not exist, prints nothing.
- `./dev complete <command> <subcommand>` prints the long flags found in
  that subcommand's arguments string, extracted with
  `grep -oE '\-\-[A-Za-z][A-Za-z0-9-]*'`.

An unknown command or subcommand prints nothing and exits 0 rather than
failing — the person is still typing, so there is no error to report.

The flag-extraction rule is what makes a `dev_verb` arguments string double
as the source of flag completions, with nothing extra to write. A
subcommand declared as:

```bash
dev_verb use '<branch> [--fallback <b>] [--fetch] [--dry-run]' 'Move every component onto <branch>'
```

gets `--fallback`, `--fetch`, and `--dry-run` completed for free, because
each matches the `--` pattern. A command file that instead writes its
arguments string as prose — `'(dry run)'` rather than `'[--dry-run]'` —
gets no flag completions for that subcommand, because nothing in the
string matches. Write the arguments string as the actual flag spelling,
not a description of it, and flag completion follows automatically.

## Complete annotated example

A command wrapping an existing `scripts/db-clone.sh` and
`scripts/db-migrate.sh`, saved as `.dev/commands/db.sh`:

```bash
#!/usr/bin/env bash
#
# ./dev db - clone and migrate the local database.
#
# Top level defines only functions. Nothing here runs a command directly;
# the dispatcher sources this file on every "./dev help" as well as on a
# real "./dev db ...", so any side effect here would run every time too.

dev_describe() {
  echo 'Clone the shared database locally and apply pending migrations'
}

dev_verbs() {
  # dev_verb <name> <arguments> <description>
  dev_verb clone   '[--yes]'   'Clone the shared database into the local Postgres container'
  dev_verb migrate ''          'Apply pending Flyway migrations to the local clone'
  dev_verb status  ''          'Show the local clone and its migration state'
}

dev_run() {
  local verb=$1
  shift

  case $verb in
    clone)   db_clone "$@" ;;
    migrate) db_migrate ;;
    status)  db_status ;;
    *)       die "unhandled subcommand: $verb" ;;
  esac
}

# --- subcommand implementations ---------------------------------------------
# Every actual action happens inside these, called only from dev_run.

db_clone() {
  if [ "${1:-}" != '--yes' ]; then
    die "$DEV_NAME db clone touches the local database container; pass --yes to confirm"
  fi
  "$DEV_ROOT/scripts/db-clone.sh"
}

db_migrate() {
  "$DEV_ROOT/scripts/db-migrate.sh"
}

db_status() {
  "$DEV_ROOT/scripts/db-status.sh"
}
```

Points this example is showing:

- The file defines only functions at the top level; `set -euo pipefail` and
  similar are unnecessary here because the dispatcher itself already runs
  under `set -euo pipefail` and sources this file into that same shell.
- `dev_describe` and `dev_verbs` only echo and register text — they never
  call `db_clone` or touch the filesystem.
- `db_clone` is a command that mutates local state others might rely on
  (the local database container), so it requires `--yes` and says so in
  its `dev_verb` description (`'[--yes]'` in the arguments column, and the
  description line does not hide the confirmation requirement).
- Every path into `$DEV_ROOT` is built from the variable, never hardcoded,
  so the command works no matter where the project is checked out.

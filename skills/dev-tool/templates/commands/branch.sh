#!/usr/bin/env bash
#
# ./dev branch - show and align the branch each component sits on.
#
# When one feature spans several submodules or sibling repositories, which
# component is on which branch is scattered and invisible. This command puts
# it in one table and moves them together.
#
# Component discovery order:
#   1. the DEV_COMPONENTS array in .dev/config.sh
#   2. the submodule paths in .gitmodules
#   3. the repository itself
#
# This command never commits, never resets, and never stashes. Stash is shared
# across the worktrees of one repository, so what one session pushes onto it
# another can pop, silently taking someone else's work. Instead, if any single
# component has uncommitted changes the whole operation is refused and the
# blocked components are listed.

dev_describe() {
  echo '여러 component 의 branch 를 한 번에 보고 맞춥니다'
}

dev_verbs() {
  dev_verb show ''                                              '각 component 의 현재 branch 와 변경 여부를 보여줍니다'
  dev_verb use  '<branch> [--fallback <b>] [--fetch] [--dry-run]' '그 branch 가 있는 component 는 그 branch 로, 없는 component 는 fallback 으로 checkout 합니다'
}

dev_run() {
  local verb=$1
  shift

  case $verb in
    show) branch_show ;;
    use)  branch_use "$@" ;;
    *)    die "unhandled subcommand: $verb" ;;
  esac
}

# --- discovering components -------------------------------------------------

branch_components() {
  if declare -p DEV_COMPONENTS >/dev/null 2>&1; then
    printf '%s\n' "${DEV_COMPONENTS[@]}"
    return 0
  fi

  if [ -f "$DEV_ROOT/.gitmodules" ]; then
    git -C "$DEV_ROOT" config --file .gitmodules --get-regexp '^submodule\..*\.path$' |
      awk '{ print $2 }'
    return 0
  fi

  echo '.'
}

branch_path() {
  case $1 in
    .) printf '%s\n' "$DEV_ROOT" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$DEV_ROOT" "$1" ;;
  esac
}

# --- reading one component ---------------------------------------------------

branch_current() {
  local path=$1 name
  name=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo '(git 저장소가 아님)'
    return 0
  }

  if [ "$name" = HEAD ]; then
    # Detached HEAD. Show the commit, since there is no branch name.
    printf '(detached %s)\n' "$(git -C "$path" rev-parse --short HEAD)"
  else
    printf '%s\n' "$name"
  fi
}

branch_is_dirty() {
  local path=$1 output
  output=$(git -C "$path" status --porcelain 2>/dev/null) || return 1
  [ -n "$output" ]
}

# branch_resolve <path> <name>
# Prints local when the branch exists locally, remote when it exists only on
# origin, and returns 1 with no output when it exists in neither.
branch_resolve() {
  local path=$1 name=$2

  if git -C "$path" rev-parse --verify --quiet "refs/heads/$name" >/dev/null 2>&1; then
    echo local
    return 0
  fi

  if git -C "$path" rev-parse --verify --quiet "refs/remotes/origin/$name" >/dev/null 2>&1; then
    echo remote
    return 0
  fi

  return 1
}

# --- show --------------------------------------------------------------------

branch_show() {
  local component path current mark

  # printf pads by byte count, but a Hangul character takes three bytes and
  # two display columns. So the branch name, whose width varies, goes last,
  # and the Hangul column only ever holds values of equal byte length.
  printf '%-14s %-8s %s\n' 'component' '변경' 'branch'
  while read -r component; do
    [ -n "$component" ] || continue
    path=$(branch_path "$component")

    if [ ! -d "$path" ]; then
      printf '%-14s %-8s %s\n' "$component" '모름' '(경로 없음)'
      continue
    fi

    current=$(branch_current "$path")

    # A path that is not a git repository cannot be asked whether it is dirty.
    # Reporting it as clean would be a lie, so report it as unknown.
    if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
      mark='모름'
    elif branch_is_dirty "$path"; then
      mark='있음'
    else
      mark='없음'
    fi

    printf '%-14s %-8s %s\n' "$component" "$mark" "$current"
  done < <(branch_components)
}

# --- use ---------------------------------------------------------------------

branch_use() {
  local wanted='' fallback=main fetch=0 dry_run=0

  while [ $# -gt 0 ]; do
    case $1 in
      --fallback) [ $# -ge 2 ] || die '--fallback 은 branch 이름이 필요합니다'; fallback=$2; shift 2 ;;
      --fetch) fetch=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -*) die "unknown option: $1" ;;
      *) [ -z "$wanted" ] || die "branch 이름은 하나만 줍니다: $wanted, $1"; wanted=$1; shift ;;
    esac
  done

  [ -n "$wanted" ] || die "쓸 branch 이름을 주십시오: $DEV_NAME branch use <branch>"

  local components=()
  local component
  while read -r component; do
    [ -n "$component" ] && components+=("$component")
  done < <(branch_components)

  [ "${#components[@]}" -gt 0 ] || die 'component 를 찾지 못했습니다.'

  if [ "$fetch" -eq 1 ]; then
    for component in "${components[@]}"; do
      local path
      path=$(branch_path "$component")
      [ -d "$path" ] || continue
      printf 'fetch %s\n' "$component" >&2
      git -C "$path" fetch --quiet origin || die "$component 에서 fetch 가 실패했습니다."
    done
  fi

  # First pass: decide everything, change nothing. A run that failed halfway
  # would leave some components moved and some not, which is the state hardest
  # to notice and hardest to undo.
  local plan_components=() plan_targets=() plan_kinds=()
  local blocked=() skipped=()

  for component in "${components[@]}"; do
    local path target kind current
    path=$(branch_path "$component")

    # A missing path or a non-repository was never movable in the first place.
    # An uninitialized submodule is the common case, and one of those must not
    # stop every other component from moving. Report it instead of blocking.
    [ -d "$path" ] || { skipped+=("$component: 경로가 없습니다"); continue; }
    git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || {
      skipped+=("$component: git 저장소가 아닙니다")
      continue
    }

    if kind=$(branch_resolve "$path" "$wanted"); then
      target=$wanted
    elif kind=$(branch_resolve "$path" "$fallback"); then
      target=$fallback
    else
      blocked+=("$component: $wanted 도 $fallback 도 없습니다")
      continue
    fi

    current=$(branch_current "$path")
    if [ "$current" = "$target" ]; then
      kind=keep
    elif branch_is_dirty "$path"; then
      # No stash. The person has to deal with their own changes.
      blocked+=("$component: 변경사항이 있습니다. 지금 $current, 옮기려던 곳 $target")
      continue
    fi

    plan_components+=("$component")
    plan_targets+=("$target")
    plan_kinds+=("$kind")
  done

  local i
  printf '계획:\n' >&2
  for i in "${!plan_components[@]}"; do
    case ${plan_kinds[$i]} in
      keep)   printf '  %-14s %s (그대로)\n' "${plan_components[$i]}" "${plan_targets[$i]}" >&2 ;;
      local)  printf '  %-14s %s\n' "${plan_components[$i]}" "${plan_targets[$i]}" >&2 ;;
      remote) printf '  %-14s %s (origin 에서 새로 만듭니다)\n' "${plan_components[$i]}" "${plan_targets[$i]}" >&2 ;;
    esac
  done

  if [ "${#skipped[@]}" -gt 0 ]; then
    printf '\n건너뜁니다:\n' >&2
    local note
    for note in "${skipped[@]}"; do
      printf '  %s\n' "$note" >&2
    done
  fi

  if [ "${#blocked[@]}" -gt 0 ]; then
    printf '\n막힌 component:\n' >&2
    local reason
    for reason in "${blocked[@]}"; do
      printf '  %s\n' "$reason" >&2
    done
    printf '\n아무것도 바꾸지 않았습니다. 변경사항은 commit 하거나 직접 되돌린 뒤 다시 실행하십시오.\n' >&2
    printf 'stash 는 worktree 사이에서 공유되므로 이 command 는 쓰지 않습니다.\n' >&2
    return 1
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf '\n--dry-run 이라 여기서 멈춥니다.\n' >&2
    return 0
  fi

  # Second pass: actually move.
  local moved=0
  for i in "${!plan_components[@]}"; do
    local path=${plan_components[$i]}
    path=$(branch_path "$path")

    case ${plan_kinds[$i]} in
      keep) continue ;;
      local)
        git -C "$path" checkout --quiet "${plan_targets[$i]}" ||
          die "${plan_components[$i]} 에서 ${plan_targets[$i]} 로 checkout 이 실패했습니다."
        ;;
      remote)
        git -C "$path" checkout --quiet -b "${plan_targets[$i]}" --track "origin/${plan_targets[$i]}" ||
          die "${plan_components[$i]} 에서 origin/${plan_targets[$i]} 를 받아오지 못했습니다."
        ;;
    esac
    [ "$moved" -eq 0 ] && printf '\n' >&2
    moved=$((moved + 1))
    printf '%-14s -> %s\n' "${plan_components[$i]}" "${plan_targets[$i]}" >&2
  done

  if [ "$moved" -eq 0 ]; then
    printf '\n옮길 것이 없습니다.\n' >&2
    return 0
  fi

  # Only true once something actually moved. Saying it after a run that
  # changed nothing sends the person looking for a change that is not there.
  if [ -f "$DEV_ROOT/.gitmodules" ]; then
    printf '\nsubmodule pointer 가 달라졌습니다. commit 할지는 따로 정하십시오.\n' >&2
  fi
}

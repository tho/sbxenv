#!/usr/bin/env bash
# Carry Claude Code state between an sbx sandbox and this Mac.
#
#   sbx-state-sync.sh [-n] SANDBOX    (-n: dry run, -h: help)
#
# Pull (sandbox -> host): everything under each agent's state root, newer
# wins (rsync --update); host files it replaces are kept under
# ~/.claude/sbx-state-sync-backups/; nothing is deleted on the host.
# Push (host -> sandbox): only sessions whose cwd is in the sandbox's
# workspace, never overwriting (rsync --ignore-existing).
# Memory indexes (MEMORY.md) skip both and are union-merged instead.
#
# Transport: rsync -e 'sbx exec -i', so the sandbox needs rsync (kits/rsync).
# Requires sbx, jq and rsync on the host; runs under macOS's bash 3.2.
# Read docs/state-sync.md.
set -euo pipefail

readonly SCRIPT_NAME=sbx-state-sync

# Prints the usage line to stdout.
usage() {
  echo "usage: $SCRIPT_NAME [-n] SANDBOX"
}

# Prints "$SCRIPT_NAME: <args>" to stderr and exits 1.
die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

dry_run=
while getopts ":nh" opt; do
  case $opt in
    n) dry_run=1 ;;
    h)
      usage
      exit 0
      ;;
    \?)
      printf '%s: unknown option -%s\n' "$SCRIPT_NAME" "$OPTARG" >&2
      usage >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi
readonly dry_run sandbox=$1

for tool in sbx jq rsync; do
  command -v "$tool" >/dev/null || die "$tool not found on this Mac"
done

sandboxes=$(sbx ls --format json) || die "'sbx ls' failed"
workspace=$(jq -r --arg n "$sandbox" \
  '.[] | select(.name == $n) | .workspaces[0] // empty' <<<"$sandboxes") ||
  die "cannot parse 'sbx ls --format json' output"
[[ -n $workspace ]] || die "no sandbox named '$sandbox' in 'sbx ls', or it has no workspace"
readonly workspace=${workspace%/}

# Runs a command in the sandbox; returns its exit status.
remote() {
  sbx exec "$sandbox" "$@"
}

remote true || die "cannot run commands in sandbox $sandbox"
remote sh -c 'command -v rsync' >/dev/null ||
  die "no rsync in sandbox $sandbox; add kits/rsync to ~/.sbxenv.yaml and recreate it"

rsync_opts=(-a --itemize-changes -e 'sbx exec -i')
mode=
if [[ -n $dry_run ]]; then
  rsync_opts+=(--dry-run)
  mode=' (dry run)'
fi
readonly rsync_opts mode

# Prints a section heading, tagged when this is a dry run.
heading() {
  printf '== %s%s\n' "$*" "$mode"
}

# Runs rsync with the common options plus "$@" and prints its itemized
# output indented, even when rsync fails part way; dies on rsync failure.
run_rsync() {
  local out status=0
  out=$(rsync "${rsync_opts[@]}" "$@") || status=$?
  if [[ -n $out ]]; then
    printf '%s\n' "$out" | sed 's/^/   /'
  elif [[ $status -eq 0 ]]; then
    echo "   nothing to move"
  fi
  [[ $status -eq 0 ]] || die "rsync exited $status"
}

# Succeeds when $1 is the workspace or a path under it (worktrees included).
owned() {
  [[ "$1/" == "$workspace"/* ]]
}

# Claude Code: ~/.claude/projects/<slug>/{*.jsonl,memory/,...}

readonly CLAUDE_REMOTE=/home/agent/.claude/projects
readonly CLAUDE_HOST=$HOME/.claude/projects
readonly WORKSPACE_SLUG=${workspace//[^A-Za-z0-9]/-}
readonly INDEX=memory/MEMORY.md
BACKUP_DIR=$HOME/.claude/sbx-state-sync-backups/$sandbox/$(date -u +%Y%m%dT%H%M%SZ)
readonly BACKUP_DIR

tmp=$(mktemp -d) || die "cannot create a temporary directory"
readonly tmp
trap 'rm -rf -- "$tmp"' EXIT

# Prints the first "cwd" recorded in the session transcripts under slug
# directory $1, or nothing when there is none.
session_cwd() {
  local cwd
  # grep fails when no transcript has a cwd (or there are no transcripts),
  # and may take SIGPIPE from head; either way the output is what counts.
  cwd=$(grep -h -m1 -o '"cwd":"[^"]*"' "$1"*.jsonl 2>/dev/null | head -1) || true
  cwd=${cwd#\"cwd\":\"}
  printf '%s' "${cwd%\"}"
}

# Prints the non-blank lines of file $2 that are not in file $1.
new_lines() {
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; next } $0 != "" && !($0 in seen)' "$1" "$2"
}

# Union-merges slug $1's MEMORY.md between the host and the sandbox: the
# host's lines as they are, then the sandbox's other non-blank lines (the
# sandbox's file as it is when the host has none). Lists the lines each
# side gains (> host, < sandbox) and writes both sides unless dry run.
# Sets the caller's merged=1 when the two sides differ.
merge_index() {
  local slug=$1
  local host_file=$CLAUDE_HOST/$slug/$INDEX remote_file=$CLAUDE_REMOTE/$slug/$INDEX
  local h=$tmp/host s=$tmp/sandbox m=$tmp/merged base other gained
  # awk 1 adds a missing final newline, as the merge below would,
  # so a file lacking one doesn't count as changed
  : >"$h"
  if [[ -f $host_file ]]; then
    awk 1 "$host_file" >"$h"
  fi
  # shellcheck disable=SC2016 # $1 expands in the sandbox's sh
  remote sh -c 'if [ -f "$1" ]; then cat -- "$1"; fi' _ "$remote_file" | awk 1 >"$s" ||
    die "cannot read $remote_file in $sandbox"
  base=$h other=$s
  if [[ ! -s $h ]]; then
    base=$s other=$h
  fi
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; print; next }
    $0 != "" && !seen[$0]++' "$base" "$other" >"$m"
  if cmp -s "$m" "$h" && cmp -s "$m" "$s"; then
    return 0
  fi

  echo "   $slug/$INDEX:"
  gained=$(new_lines "$h" "$m")
  [[ -z $gained ]] || printf '%s\n' "$gained" | sed 's/^/     > /'
  gained=$(new_lines "$s" "$m")
  [[ -z $gained ]] || printf '%s\n' "$gained" | sed 's/^/     < /'
  merged=1
  [[ -z $dry_run ]] || return 0

  if ! cmp -s "$m" "$h"; then
    mkdir -p -- "${host_file%/*}"
    cat -- "$m" >"$host_file"
  fi
  if ! cmp -s "$m" "$s"; then
    # shellcheck disable=SC2016 # $1 expands in the sandbox's sh
    sbx exec -i "$sandbox" sh -c 'mkdir -p "${1%/*}" && cat >"$1"' _ "$remote_file" <"$m" ||
      die "cannot write $remote_file in $sandbox"
  fi
}

# Pulls every Claude slug directory from the sandbox, then pushes the host
# slug directories that belong to the sandbox's workspace, then merges the
# memory indexes of both.
claude_sync() {
  if ! remote test -d "$CLAUDE_REMOTE"; then
    heading "claude: no $CLAUDE_REMOTE in $sandbox, skipped"
    return 0
  fi
  mkdir -p -- "$CLAUDE_HOST"

  heading "claude: pull $sandbox -> host"
  # sbx's volume marker isn't Claude state
  run_rsync --update --exclude="/*/$INDEX" --exclude=/.sbx-volume-initialized/ --backup --backup-dir="$BACKUP_DIR" \
    "$sandbox:$CLAUDE_REMOTE/" "$CLAUDE_HOST/"
  if [[ -d $BACKUP_DIR ]]; then
    echo "   replaced host files saved in $BACKUP_DIR"
  fi

  heading "claude: push host -> $sandbox (sessions in $workspace)"
  local dir slug cwd pushed='' indexed='' merged=''
  for dir in "$CLAUDE_HOST"/*/; do
    [[ -d $dir ]] || continue
    slug=${dir%/}
    slug=${slug##*/}
    # Every cwd under the workspace slugs to this prefix, so other slugs
    # need no grep; the cwd check below weeds out siblings like repo-kits.
    [[ $slug == "$WORKSPACE_SLUG" || $slug == "$WORKSPACE_SLUG"-* ]] || continue
    cwd=$(session_cwd "$dir")
    if [[ -n $cwd ]]; then
      owned "$cwd" || continue
    else
      [[ $slug == "$WORKSPACE_SLUG" ]] || continue
    fi
    pushed=1
    [[ ! -f $dir$INDEX ]] || indexed+=$slug$'\n'
    echo "   $slug:"
    run_rsync --ignore-existing --exclude="/$INDEX" "$dir" "$sandbox:$CLAUDE_REMOTE/$slug/"
  done
  [[ -n $pushed ]] || echo "   no slug directories for $workspace on host"

  heading "claude: merge memory indexes ($INDEX)"
  # shellcheck disable=SC2016 # $1 and $f expand in the sandbox's sh
  indexed+=$(remote sh -c 'cd "$1" || exit
    for f in */memory/MEMORY.md; do if [ -f "$f" ]; then echo "${f%%/*}"; fi; done' \
    _ "$CLAUDE_REMOTE") || die "cannot list memory indexes in $sandbox"
  # fd 3 keeps sbx exec in merge_index off the slug list
  while IFS= read -r -u 3 slug; do
    [[ -z $slug ]] || merge_index "$slug"
  done 3< <(printf '%s\n' "$indexed" | sort -u)
  [[ -n $merged ]] || echo "   nothing to move"
}

claude_sync

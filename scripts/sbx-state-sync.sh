#!/usr/bin/env bash
# Carry Claude Code state between an sbx sandbox and this Mac.
#
#   sbx-state-sync.sh [-n] SANDBOX    (-n: dry run, -h: help)
#
# Pull (sandbox -> host): everything under each agent's state root, newer
# wins (rsync --update); nothing is deleted on the host.
# Push (host -> sandbox): only sessions whose cwd is in the sandbox's
# workspace, never overwriting (rsync --ignore-existing).
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
    \?) die "unknown option -$OPTARG" ;;
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

remote sh -c 'command -v rsync' >/dev/null 2>&1 ||
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
# output indented; returns rsync's exit status.
run_rsync() {
  local out
  out=$(rsync "${rsync_opts[@]}" "$@") || return
  if [[ -z $out ]]; then
    echo "   nothing to move"
    return 0
  fi
  printf '%s\n' "$out" | sed 's/^/   /'
}

# Succeeds when $1 is the workspace or a path under it (worktrees included).
owned() {
  [[ "$1/" == "$workspace"/* ]]
}

# Claude Code: ~/.claude/projects/<slug>/{*.jsonl,memory/,...}

readonly CLAUDE_REMOTE=/home/agent/.claude/projects
readonly CLAUDE_HOST=$HOME/.claude/projects
readonly WORKSPACE_SLUG=${workspace//[^A-Za-z0-9]/-}

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

# Pulls every Claude slug directory from the sandbox, then pushes the host
# slug directories that belong to the sandbox's workspace.
claude_sync() {
  if ! remote test -d "$CLAUDE_REMOTE"; then
    heading "claude: no $CLAUDE_REMOTE in $sandbox, skipped"
    return 0
  fi
  mkdir -p -- "$CLAUDE_HOST"

  heading "claude: pull $sandbox -> host"
  run_rsync --update "$sandbox:$CLAUDE_REMOTE/" "$CLAUDE_HOST/"

  heading "claude: push host -> $sandbox (sessions in $workspace)"
  local dir slug cwd pushed=
  for dir in "$CLAUDE_HOST"/*/; do
    [[ -d $dir ]] || continue
    slug=${dir%/}
    slug=${slug##*/}
    cwd=$(session_cwd "$dir")
    if [[ -n $cwd ]]; then
      owned "$cwd" || continue
    else
      [[ $slug == "$WORKSPACE_SLUG" ]] || continue
    fi
    pushed=1
    echo "   $slug:"
    run_rsync --ignore-existing "$dir" "$sandbox:$CLAUDE_REMOTE/$slug/"
  done
  [[ -n $pushed ]] || echo "   no slug directories for $workspace on host"
}

claude_sync

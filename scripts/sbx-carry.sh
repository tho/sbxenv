#!/usr/bin/env bash
# Carry a sandbox's whole clone, .git and ignored files included, across a
# recreate, as a tar archive on this Mac.
#
#   sbx-carry.sh save    [-n NAME] [-f ARCHIVE] [-y]
#   sbx-carry.sh restore [-n NAME] [-f ARCHIVE] [-y] [-k]
#
#   -n, --name NAME  sandbox name, as passed to `sbx env run --name`;
#                    default: the name `sbx env run` uses in this directory
#   -f ARCHIVE       archive path; default ~/.cache/sbx-carry/<name>.tgz
#   -y               don't ask before overwriting an archive (save) or
#                    replacing the clone (restore)
#   -k               keep the archive after a restore
#
# Workflow, from the root of the repo's host checkout:
#
#   sbx-carry.sh save && sbx env rm && sbx env run --detach
#   sbx-carry.sh restore
#
# restore empties the clone, extracts the archive and then deletes it. An
# archive that still exists is therefore work not yet restored, and save asks
# before overwriting it.
#
# Transport: tar streamed over ssh to <name>.sbx, so run `sbx setup ssh` once.
# Requires sbx, ssh and git on the host; runs under macOS's bash 3.2.
set -euo pipefail
set -f
umask 077

readonly SCRIPT_NAME=sbx-carry

# Prints the usage lines to stdout.
usage() {
  echo "usage: $SCRIPT_NAME save    [-n NAME] [-f ARCHIVE] [-y]"
  echo "       $SCRIPT_NAME restore [-n NAME] [-f ARCHIVE] [-y] [-k]"
}

# Prints "$SCRIPT_NAME: <args>" to stderr and exits 1.
die() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

# Asks the question in $1 and returns 0 only on a "y" answer. Always returns
# 0 when -y was given.
confirm() {
  local answer
  [[ -z $assume_yes ]] || return 0
  printf '%s [y/N] ' "$1"
  read -r answer || return 1
  [[ $answer == [yY] ]]
}

# Prints the sandbox name `sbx env run` would use in the current directory.
# sbx resolves it from --name, the env files' name: and <agent>-<directory>,
# so ask sbx rather than rebuild that here.
derived_name() {
  local plan name
  # A plan with pending changes may exit non-zero; only the Name line matters.
  plan=$(sbx env plan --skip-host-commands 2>/dev/null) || true
  name=$(awk '$1 == "Name:" { print $2 }' <<<"$plan")
  [[ -n $name ]] || return 1
  printf '%s\n' "$name"
}

case ${1:-} in
  save | restore) readonly action=$1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
shift

sandbox=
archive=
assume_yes=
keep=
while [[ $# -gt 0 ]]; do
  case $1 in
    -n | --name | -f)
      [[ $# -ge 2 ]] || die "$1 requires an argument"
      if [[ $1 == -f ]]; then archive=$2; else sandbox=$2; fi
      shift 2
      ;;
    -y)
      assume_yes=1
      shift
      ;;
    -k)
      [[ $action == restore ]] || die "-k only applies to restore"
      keep=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

# sbx names the sandbox after, and clones, the directory it runs in.
dir=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git checkout"
readonly dir
[[ $(pwd -P) == "$dir" ]] ||
  die "run from the checkout's root, $dir, as with sbx env run"

if [[ -z $sandbox ]]; then
  sandbox=$(derived_name) ||
    die "can't get the sandbox name from sbx env plan; pass -n NAME"
fi
readonly sandbox
readonly name_re='^[A-Za-z0-9][A-Za-z0-9.-]*$'
[[ $sandbox =~ $name_re ]] || die "invalid sandbox name: $sandbox"
readonly host="$sandbox.sbx"
readonly archive=${archive:-${XDG_CACHE_HOME:-$HOME/.cache}/sbx-carry/$sandbox.tgz}

# ssh joins its arguments into one string for the remote shell, so the path
# is quoted here.
remote_dir=$(printf '%q' "$dir")
readonly remote_dir

case $action in
  save)
    if [[ -e $archive ]]; then
      confirm "$archive, saved $(date -r "$archive" '+%Y-%m-%d %H:%M'), was never restored. Overwrite it?" ||
        die "kept the existing archive"
    fi
    mkdir -p -- "$(dirname -- "$archive")"
    readonly part="$archive.part"
    trap 'rm -f -- "$part"' EXIT
    ssh -T "$host" "tar -C $remote_dir -czf - ." >"$part" ||
      die "saving $host:$dir failed"
    tar -tzf "$part" >/dev/null || die "archive is unreadable, kept nothing"
    mv -f -- "$part" "$archive"
    echo "saved $host:$dir to $archive ($(du -h -- "$archive" | cut -f1 | tr -d ' '))"
    echo "it may hold secrets; restore deletes it"
    ;;
  restore)
    [[ -r $archive ]] || die "no archive at $archive"
    confirm "Replace everything in $host:$dir with $archive, saved $(date -r "$archive" '+%Y-%m-%d %H:%M')?" ||
      die "aborted"
    # The clone is its own disk: empty it, but keep the mount point and the
    # filesystem's lost+found.
    ssh -T "$host" "cd $remote_dir && find . -mindepth 1 -maxdepth 1 ! -name lost+found -exec rm -rf {} + && tar -xzpf -" <"$archive" ||
      die "restoring to $host:$dir failed; the archive is kept"
    echo "restored $archive to $host:$dir"
    if [[ -n $keep ]]; then
      echo "kept the archive; it may hold secrets"
    else
      rm -f -- "$archive"
      echo "deleted the archive"
    fi
    ;;
esac

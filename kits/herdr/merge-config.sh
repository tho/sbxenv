#!/bin/sh
# Merge this kit's keys into the herdr server config, keeping all others.
#
#   merge-config.sh WORKTREE_DIR [CONFIG]   (default ~/.config/herdr/config.toml, created if missing)
#
# Each key is replaced in its [table], appended to it, or added in a new
# table; default_key only fills a missing key. If the result fails
# `herdr config check`, CONFIG is left untouched and this exits 1.
set -eu

worktree_dir=$1
config=${2:-"$HOME/.config/herdr/config.toml"}
herdr=${HERDR:-/usr/local/bin/herdr}

# Goes into a TOML basic string unescaped: refuse ", \ and control characters
# (newline separately: grep reads lines).
nl='
'
case $worktree_dir in *"$nl"*) bad=1 ;; *) bad= ;; esac
if [ -n "$bad" ] || printf %s "$worktree_dir" | LC_ALL=C grep -q '["\\[:cntrl:]]'; then
  echo "merge-config: unsupported character in worktree dir" >&2
  exit 2
fi

# set_key TABLE KEY VALUE: rewrite stdin to stdout with TABLE.KEY = VALUE.
# default_key TABLE KEY VALUE: the same, but an existing TABLE.KEY is kept.
set_key() { merge_key 0 "$@"; }
default_key() { merge_key 1 "$@"; }
merge_key() {
  awk -v keep="$1" -v table="$2" -v key="$3" -v value="$4" '
    function header_name(line) {
      sub(/^[ \t]*\[[ \t]*/, "", line)
      sub(/[ \t]*\].*$/, "", line)
      return line
    }
    function flush_blanks() { for (; blanks > 0; blanks--) print "" }
    function add_key() { print key " = " value; done = 1 }
    # Any [table] or [[array]] header ends the current table.
    /^[ \t]*\[/ {
      if (in_table && !done) add_key()
      flush_blanks()
      in_table = ($0 !~ /^[ \t]*\[\[/ && header_name($0) == table)
      if (in_table) seen = 1
      print
      next
    }
    # Hold blank lines so a key added at the end of a table goes before them.
    /^[ \t]*$/ { blanks++; next }
    {
      flush_blanks()
      if (in_table && !done && $0 ~ ("^[ \t]*" key "[ \t]*=")) {
        if (keep) { print; done = 1 } else add_key()
        next
      }
      print
    }
    END {
      if (in_table && !done) add_key()
      else if (!seen) { if (NR > 0) print ""; print "[" table "]"; add_key(); blanks = 0 }
      flush_blanks()
    }
  '
}

mkdir -p "$(dirname "$config")"
tmp=$(mktemp "$config.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{ cat "$config" 2>/dev/null || true; } |
  set_key update version_check false |
  set_key update manifest_check false |
  set_key worktrees directory "\"$worktree_dir\"" |
  default_key terminal default_shell '"/bin/bash"' >"$tmp"

# Fail closed on any `herdr config check` diagnostic the merge introduced,
# e.g. a parse error because the file used dotted keys or inline tables.
# Warnings the file already had (unknown keys or sections) don't block it.
check() { HERDR_CONFIG_PATH=$1 "$herdr" config check 2>&1 || true; }
before=$( [ ! -f "$config" ] || check "$config" )
added=$(check "$tmp" | grep -vxF -e 'config: ok' -e 'config: issues found' |
  { if [ -n "$before" ]; then grep -vxF -e "$before"; else cat; fi; } || true)
if [ -n "$added" ]; then
  echo "merge-config: merged $config fails \`herdr config check\`; left it unchanged:" >&2
  printf '%s\n' "$added" >&2
  exit 1
fi
if cmp -s "$tmp" "$config"; then
  exit 0
fi
[ ! -f "$config" ] || chmod --reference="$config" "$tmp" 2>/dev/null || true
mv -f "$tmp" "$config"
trap - EXIT

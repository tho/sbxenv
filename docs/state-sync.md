# State sync

Claude Code keeps its session transcripts and per-project memory under `$HOME`. In a sandbox that is the sandbox's `$HOME`: the host never sees it, and a sandbox with another name starts cold. [`scripts/sbx-state-sync.sh`](../scripts/sbx-state-sync.sh) carries that state out to your Mac and back into sandboxes, by hand, when you decide to.

Claude Code's state volumes survive `sbx env rm` for a sandbox of the same name, see [Recreate](sandboxes.md#recreate). The script is for the rest: reading sandbox transcripts on the Mac, seeding a sandbox with a different name, and letting memory compound.

## Setup

- The sandbox gets rsync from [`kits/config`](../kits/config). The script's transport is `rsync -e 'sbx exec -i'`, so the sandbox needs rsync; the macOS one on your Mac is enough. No `sbx setup ssh` is needed.
- Put the script on your `PATH` if you like, by symlink or copy. It needs `sbx` and `jq`.

## Usage

```sh
sbx-state-sync.sh -n sbx-kit-shell-myrepo          # list what would move, per direction
sbx-state-sync.sh sbx-kit-shell-myrepo             # move it
```

The argument is the sandbox name from `sbx ls`. A stopped sandbox is started. The output itemizes every file that crossed, in rsync's `--itemize-changes` form (`>f` pulled, `<f` pushed), and every memory index line each side gains (`>` host, `<` sandbox).

Under `~/.claude/projects/`, when the sandbox has it:

1. **Pull**, sandbox to host: every project slug directory, newer copy wins (`rsync --update`). A host file the pull replaces is first copied to `~/.claude/sbx-state-sync-backups/<sandbox>/<UTC time>/`, and that path is printed. The backups are never pruned.
2. **Push**, host to sandbox: only the sessions that belong to the sandbox's workspace, by the `cwd` recorded in the session, so a sibling repo such as `myrepo-kits` stays out and a worktree under `<workspace>/.worktrees/` goes in. A file the sandbox already has is never overwritten (`rsync --ignore-existing`).
3. **Merge** `<slug>/memory/MEMORY.md`, Claude Code's memory index, which both passes skip: the host's lines as they are, then the sandbox's lines the host lacks, written to both sides. This covers every slug whose index is in the sandbox, plus pushed slugs whose index is on the host.

Pushed are the slug directories whose sessions' `cwd` is under the workspace, and memory-only slug directories when the slug is the workspace's. Slug names can't be matched by prefix, because Claude Code turns both `/` and `-` into `-`. `<slug>/memory/` moves with the rest of its slug directory.

Not synced: settings, todos, plugins, `history.jsonl`.

## Why nothing is deleted

Neither pass uses `--delete`.

- Sessions: Claude Code deletes transcripts older than `cleanupPeriodDays` on its own. In a sandbox that cleanup would spread to the host as deletions. Without `--delete`, `-a` keeps the mtimes, and the host's own cleanup ages pulled transcripts out, the same as if there were no sandbox. Also, the pull covers the whole projects root, so `--delete` would wipe every host project the sandbox doesn't have.
- Memory: Claude Code on the Mac and in the sandbox both write a repo's memory, so neither side is the source of truth. An earlier version mirrored the sandbox's `memory/` with `--delete`. Its first real run deleted a memory file written on the host: pull runs before push, so the file was deleted before the push could deliver it.

## Conflicts

Sync never overwrites a sandbox file. The pull replacing a host file is the only overwrite, and that is where an edit can be lost; the backup keeps the replaced copy. For a file changed since the last sync:

| Changed on | Result |
| --- | --- |
| Sandbox only | Pulled. |
| Host only | Stays on the host and is never pushed, because the sandbox has the file. The next sandbox write to it makes the sandbox copy newer, and the pull after that replaces the host edit. |
| Both, sandbox last | The host edit is replaced and goes to the backup. |
| Both, host last | The host keeps its version, and the sandbox edit never reaches the host. It is lost when the sandbox is removed, unless the sandbox writes the file again. |
| One side, new file | Copied to the other side (push only for the workspace's slugs). |
| One side, deleted | Comes back from the other side. |

Clock skew between the Mac and the sandbox decides near-ties.

`MEMORY.md` is the exception. Each new memory on either side appends a line to it, so newest-wins would drop one side's lines and leave their fact files unindexed, and Claude never loads an unindexed memory. The merge keeps both sides' lines, with two side effects:

- A line removed on one side comes back from the other.
- A line edited on one side keeps the old version next to the new one.

To remove or reword a line, change it on both sides before the next sync, for example on the Mac and with `sbx exec SANDBOX` in the sandbox.

Fact files edited in place, not just created, follow the table. Sessions are safe because each one is appended to by a single writer, unless you resume the same session on both sides.

To keep conflicts rare:

- Sync often.
- Run `-n` first. A `>f` line for a memory file you edited on the Mac means the pull will replace it.
- Between syncs, edit a repo's memory files on one side only, preferably the sandbox.

## Limitations

- Only Claude Code. Codex, Copilot and Cursor are not synced; a Codex profile was designed but not tested, so it is not shipped.
- Deleting a memory file or an index line sticks only if it is deleted on both sides.

# State sync

Claude Code keeps its session transcripts and per-project memory under `$HOME`. In a sandbox that is the sandbox's `$HOME`: the host never sees it, and a sandbox with another name starts cold. [`scripts/sbx-state-sync.sh`](../scripts/sbx-state-sync.sh) carries that state out to your Mac and back into sandboxes, by hand, when you decide to.

Claude Code's state volumes survive `sbx env rm` for a sandbox of the same name, see [Recreate](sandboxes.md#recreate). The script is for the rest: reading sandbox transcripts on the Mac, seeding a sandbox with a different name, and letting memory compound.

## Setup

- Add [`kits/rsync`](../kits/rsync) to `~/.sbxenv.yaml` and recreate the sandbox. The script's transport is `rsync -e 'sbx exec -i'`, so the sandbox needs rsync; the macOS one on your Mac is enough. No `sbx setup ssh` is needed.
- Put the script on your `PATH` if you like, by symlink or copy. It needs `sbx` and `jq`.

## Usage

```sh
sbx-state-sync.sh -n sbx-kit-shell-myrepo          # list what would move, per direction
sbx-state-sync.sh sbx-kit-shell-myrepo             # move it
```

The argument is the sandbox name from `sbx ls`. A stopped sandbox is started. The output itemizes every file that crossed, in rsync's `--itemize-changes` form (`>f` pulled, `<f` pushed, `*deleting` removed on the host).

Under `~/.claude/projects/`, when the sandbox has it:

1. **Pull**, sandbox to host: every project slug directory, newer copy wins (`rsync --update`). Nothing is deleted on the host.
2. **Push**, host to sandbox: only the sessions that belong to the sandbox's workspace, by the `cwd` recorded in the session, so a sibling repo such as `myrepo-kits` stays out and a worktree under `<workspace>/.worktrees/` goes in. A file the sandbox already has is never overwritten (`rsync --ignore-existing`).

Pushed are the slug directories whose sessions' `cwd` is under the workspace, and memory-only slug directories when the slug is the workspace's. `<slug>/memory/` moves with the rest of its slug directory, both ways; nothing is deleted.

Not synced: settings, todos, plugins, `history.jsonl`.

## Limitations

- A host edit to a memory file the sandbox already has is not pushed, and the next pull replaces it when the sandbox copy is newer.
- Deleting a memory file does not stick unless it is deleted on both sides: the next sync brings it back from the side that still has it.
- `MEMORY.md`, Claude Code's memory index, is one file: when both the sandbox and Claude Code on the Mac add lines to it for the same repo, the newer copy wins on pull and the other side's lines are gone, leaving their fact files unindexed. Re-add the lines by hand.
- Only Claude Code. Codex, Copilot and Cursor are not synced; a Codex profile was designed but not tested, so it is not shipped.
- Clock skew between the Mac and the sandbox decides `--update` ties.

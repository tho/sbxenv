# Sandboxes

## Names

For a second sandbox on the same repo, pass a name, as in `sbx env run --name myrepo-spike`. Pass the same `--name` to every `sbx env` command for that sandbox.

Two repos with the same directory name get the same sandbox name, and with it the same agent sessions (see [Recreate](#recreate)). Give one of them its own `--name`. Otherwise `sbx env run --force` in the second repo silently attaches to the first repo's sandbox.

## The clone

The clone gets your checkout's remotes, so its `origin` is usually the same as yours, such as a GitHub repo. Your checkout itself is mounted read-only at `/run/sandbox/source`, and `git fetch /run/sandbox/source` picks up host commits made after create.

Put worktrees you create by hand under the clone's `.worktrees/`, which git in the sandbox ignores.

## Disks

Disk sizes are fixed when the sandbox is created. The clone has its own disk of about 50 GB, and the root disk, which holds `$HOME`, has 20 GB. For big repos, set a larger clone disk in `~/.sbxenv.yaml`:

```yaml
sandboxOptions:
  clonedWorkspaceSize: "100g"
```

`rootSize` and `dockerSize` set the other disks. For one sandbox, set the environment variable instead:

```sh
DOCKER_SANDBOXES_CLONED_WORKSPACE_SIZE=100g sbx env run
```

## GitHub

With the `github` secret set, agents can push to GitHub and open pull requests with `gh pr create`. The secret isn't injected on `uploads.github.com`, so `gh release upload` doesn't authenticate.

## Recreate

`sbx env rm` deletes the sandbox and its clone, so fetch first. `sbx env run` then creates a new one.

Only the agents' sessions survive, in directories on your Mac, one per sandbox name. A new sandbox with the same name gets them back. `sbx inspect <name>` shows the directories under `host_mounts`.

| Kit | Keeps |
|---|---|
| `sbx/claude-sessions` | `~/.claude/projects` (sessions and memory), `sessions`, `todos`, `shell-snapshots`, `statsig` |
| `sbx/codex-sessions` | `~/.codex/sessions`, `archived_sessions` |
| `sbx/cursor-sessions` | `~/.cursor/chats`, `acp-sessions` |
| `sbx/pi-sessions` | `~/.pi/agent/sessions`, `extensions`, `skills`, `prompts`, `themes` |

## Upgrade

1. Carry the changes into `~/.sbxenv.yaml`, keeping your options. Without a checkout, this shows them:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/tho/sbxenv/main/sbxenv.remote.yaml | diff - ~/.sbxenv.yaml
   ```

   From a checkout:

   ```sh
   git pull
   sed "s|/path/to/sbxenv|$PWD|" sbxenv.example.yaml | diff - ~/.sbxenv.yaml
   ```

2. In every repo whose sandbox has unfetched work, run `git fetch sandbox-<name>`.
3. Recreate each sandbox with `sbx env rm`, then `sbx env run`. An existing sandbox doesn't pick up changes to `~/.sbxenv.yaml` or the kits.

To bump a pin yourself, see [Bump a pinned version](../kits/README.md#bump-a-pinned-version).

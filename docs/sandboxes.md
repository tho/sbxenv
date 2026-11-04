# Sandboxes

## Names

For a second sandbox on the same repo, pass a name, as in `sbx env run --name myrepo-spike`. Pass the same `--name` to every `sbx env` command for that sandbox.

Two repos with the same directory name get the same sandbox name. Claude Code's sessions and memory are shared by all sandboxes anyway, see [Recreate](#recreate). Give one of them its own `--name` on every `sbx env` command. Otherwise `sbx env run --force` in the second repo silently attaches to the first repo's sandbox.

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

With the `github` secret set, agents can push to GitHub, for example to `origin`, and open pull requests with `gh pr create`.
The secret isn't injected on `uploads.github.com`, so `gh release upload` doesn't authenticate.

## Recreate

`sbx env rm` deletes the sandbox and its clone, so fetch first. `sbx env run` then creates a new one.

With `sbx/claude-sessions` in `~/.sbxenv.yaml`, Claude Code's `~/.claude/projects`, `sessions`, `todos`, `shell-snapshots` and `statsig` are symlinks into `/home/agent/claude-history`, a directory on your Mac that sbx owns and every sandbox with that kit shares. `sbx env rm` leaves it in place, so any new sandbox gets the sessions and memory back, whatever its name. It lives under `~/Library/Application Support/com.docker.sandboxes/sandboxes/kit-host-mounts/`; `sbx inspect <name>` shows the exact path under `host_mounts`. The rest of `$HOME` starts fresh.

Before sbx 0.51.0, the Claude mixin kept that state in volumes tied to the sandbox name. A sandbox created then keeps its volumes, but nothing moves them into the shared directory. Pull them with [`sbx-state-sync.sh`](state-sync.md) before removing it, then push into a new sandbox.

## Upgrade

1. Carry the changes into `~/.sbxenv.yaml`, keeping your options. Without a checkout, this shows them, including any kit whose pinned commit moved:

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

Sandboxes from before sbx 0.51.0 are named `sbx-kit-shell-<repo>`, after the old workload kit, and `sbx env rm` with the new `~/.sbxenv.yaml` doesn't find them. Fetch their work, sync their Claude Code state out as [Recreate](#recreate) describes, then remove them with `sbx rm sbx-kit-shell-<repo>`.

To bump a pin yourself, see [Bump a pinned version](../kits/README.md#bump-a-pinned-version).

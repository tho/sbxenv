# Sandboxes

## Names

For a second sandbox on the same repo, pass a name, as in `sbx env run --name myrepo-spike`. Pass the same `--name` to every `sbx env` command for that sandbox.

Two repos with the same directory name get the same sandbox name and share Claude Code's state volumes, so old transcripts carry over. Give one of them its own `--name` on every `sbx env` command. Otherwise `sbx env run --force` in the second repo silently attaches to the first repo's sandbox.

## The clone

The clone gets your checkout's remotes, so its `origin` is usually the same as yours, such as a GitHub repo. Your checkout itself is mounted read-only at `/run/sandbox/source`, and `git fetch /run/sandbox/source` picks up host commits made after create.

Put worktrees you create by hand under the clone's `.worktrees/`, which git in the sandbox ignores.

## Disks

Disk sizes are fixed when the sandbox is created. The clone has its own disk of about 50 GB (`DOCKER_SANDBOXES_CLONED_WORKSPACE_SIZE`), and the root disk, which holds `$HOME`, has 20 GB (`DOCKER_SANDBOXES_ROOT_SIZE`). For a big repo, create the sandbox with a larger clone disk:

```sh
DOCKER_SANDBOXES_CLONED_WORKSPACE_SIZE=100g sbx env run
```

## GitHub

With the `github` secret set, agents can push to GitHub, for example to `origin`, and open pull requests with `gh pr create`.
The secret isn't injected on `uploads.github.com`, so `gh release upload` doesn't authenticate.

## Recreate

`sbx env rm` deletes the sandbox and its clone, so fetch first. `sbx env run` then creates a new one.

Claude Code stores its state, such as `~/.claude/projects`, in volumes tied to the sandbox name. `sbx env rm` leaves them in place, and a new sandbox with the same name gets them back. The rest of `$HOME` starts fresh. For Herdr, see [After a recreate](herdr.md#after-a-recreate).

## Upgrade

1. Carry the new release's changes into `~/.sbxenv.yaml`, keeping your options. Without a checkout, this shows them for a release from the [tags](https://github.com/tho/sbxenv/tags), such as `v0.2.0`:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/tho/sbxenv/v0.2.0/sbxenv.remote.yaml | diff - ~/.sbxenv.yaml
   ```

   From a checkout:

   ```sh
   git pull
   sed "s|/path/to/sbxenv|$PWD|" sbxenv.example.yaml | diff - ~/.sbxenv.yaml
   ```

2. In every repo whose sandbox has unfetched work, run `git fetch sandbox-<name>`.
3. Recreate each sandbox with `sbx env rm`, then `sbx env run`. An existing sandbox doesn't pick up changes to `~/.sbxenv.yaml` or the kits.

If you use Herdr, upgrade it on your Mac along with `kits/herdr`. To bump a pin yourself, see [Bump a pinned version](../kits/README.md#bump-a-pinned-version).

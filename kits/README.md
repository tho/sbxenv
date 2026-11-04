# Kits

sbxenv ships one kit, [`config`](config): everything sbxenv adds to Docker's kits. To add a tool or setting, put it in your dotfiles if they can express it, otherwise in `config`. Don't add a kit.

Kits follow the [sandbox kit spec v3](https://github.com/docker/sandbox-kit-spec). For more examples, see the `v3` branch of [docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib/tree/v3).

## Layout

A kit is a directory with a `<kit>.yaml` descriptor and, usually, a `<kit>.dockerfile` recipe:

- [`config.yaml`](config/config.yaml): args, capabilities and hooks
- [`config.dockerfile`](config/config.dockerfile): pinned binaries (chezmoi, uv)

Patterns to copy from `config`:

| Pattern | Where |
|---|---|
| Pinned binary, shadowing a base-image one through `PATH` order | uv in the recipe |
| Root `install` hook that runs `apt-get` | rsync |
| Create-time arg passed to a hook through `env:` | `dotfiles` |
| `git-identity@1`, `agent-skills@1`, `network-policy@1` | `capabilities` |
| `install.allow` for an apt source and a git clone | `network-policy@1` |

## Descriptor

- Write a mixin (`kind: mixin`). A sandbox has exactly one workload kit, here `sbx/shell`.
- Args:
  - An arg with `buildArg:` is fixed at build, so changing it rebuilds the kit. Args with `env:`, or with no export, resolve at create. Use those for per-sandbox values, such as `dotfiles`.
  - Never interpolate an arg into shell code. Pass it in `env:`, as `config` does with `dotfiles`, or as its own argv element.
  - Fit each arg's `pattern` to where the value lands, such as a TOML string or a command-line argument.
- Put fixed environment variables in the recipe's `ENV`, not in args.
- Write `/home/agent` in paths, not `${{ kit.env.HOME }}`.

## Recipe

Follow [`config.dockerfile`](config/config.dockerfile):

- One `ADD --checksum` download per tool and architecture.
- A build stage that fails unless each binary reports its exact pinned version.
- A `FROM scratch` overlay of root-owned files, with nothing under `/home` and no `ENTRYPOINT`.
- Release assets that run on the sandbox's Debian trixie: static builds, or glibc builds that need glibc 2.41 or older.

## Hooks

- **When:** `install` hooks run once at create. `startup` hooks run on every boot, so they must be idempotent. At create, all `install` hooks run before any `startup` hook.
- **Order across kits:** `requires` and `integrates` both run the named kits' hooks first; `requires` also fails the composition when they're missing. The names match other kits' `provides`. Kits with no such dependency run sorted by kit reference, not in list order, so local kits (`/…`) run before `docker.io/…` ones, but `git+https://…` ones run after. `sbx/claude-sessions` provides no name, so `config` can't order itself against it; its install hook, which turns `~/.claude/projects` and siblings into symlinks, runs before or after `config`'s depending on how `~/.sbxenv.yaml` names `config`. Within a kit, hooks run in list order.
- **Environment:** a hook sees only the variables in its `env:`, plus `PATH`, `HOME`, `TERM` and a few shell basics.
- **Late files:** use `startup` to edit files written after the `install` hooks. sbx adds `core.excludesFile` and `includeIf` to the git config then, and the dotfiles apply may write files a kit also edits.
- **Shared files:** to share a file with dotfiles or another kit, merge into it from a hook, not with `lifecycle@1` `files`. Set only your own keys, and fill preference keys only when they're missing.
- **Failures:** a failing hook fails the create. If the sandbox works without what the hook does, print what failed and how to redo it, prefixed `<kit> kit:`, and exit 0.

## Capabilities

- `network-policy@1`: `install.allow` hosts are open only while `install` hooks run. `runtime.allow` hosts stay open.
- `agent-skill@1` bundles one skill from the image. `agent-skills@1` declares a skills directory. Each bundled skill appears in every skills directory that the agent mixins and `config` declare. An `agent-skill@1` `path` can't use a create-time arg or `${{ kit.env.* }}`.

## Versions

- Bump `version` in `config.yaml` on any change to the kit, pin bumps included. A commit `ref=` carries no version, so sbx takes it from the descriptor.
- Docker's kits are pinned by tag in [`sbxenv.example.yaml`](../sbxenv.example.yaml) and [`sbxenv.remote.yaml`](../sbxenv.remote.yaml). Read the comments there before changing one.
- After any bump, recreate your sandboxes as [Upgrade](../docs/sandboxes.md#upgrade) describes.

### Bump a pinned version

1. In `config.yaml`, change the tool's `args.<tool>Version.default`.
2. In `config.dockerfile`, change both of its `--checksum` digests.
3. In `config.yaml`, bump `version`.

| Tool | Digests from | Provenance check |
|---|---|---|
| chezmoi | `chezmoi_<ver>_checksums.txt` (`linux-musl_amd64`, `linux_arm64`) | `cosign verify-blob --key chezmoi_cosign.pub --bundle chezmoi_<ver>_checksums.txt.sigstore.json chezmoi_<ver>_checksums.txt` |
| uv | the release's `<asset>.sha256` files | `gh attestation verify <asset> -R astral-sh/uv` |

After a uv bump, run `uv --version` in a sandbox on Apple silicon. The build runs on 4K pages, so it can't catch the 16K-page failure `config.yaml` describes.

## Try a change

Set the `config` kit's `source:` in `~/.sbxenv.yaml` to your checkout's `kits/config` by absolute path, then create a sandbox.

## Publish

Users download `sbxenv.remote.yaml` from `main`. It pins `kits/config` to a full commit SHA in `ref=`: the last commit that changed the kit. A kit change reaches users only when that `ref=` moves.

1. Make any change to one env file in the other too. Outside the header comments, they differ only in how they name the local kit; `make lint` checks this.
2. Commit the kit change. `make stale-kits` now fails, because the `ref=` is behind `HEAD`.
3. In a second commit, set the `ref=` to `git log -1 --format=%H -- kits/config` and run `make lint`. A commit can't contain its own SHA, so this must be a separate commit.
4. Push both commits together. A `ref=` that names an unpushed commit breaks every create from `main`.

A `pre-push` hook that runs `make stale-kits` blocks a push with a stale `ref=`. Install it once per clone:

```sh
printf '#!/bin/sh\nexec make stale-kits\n' > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

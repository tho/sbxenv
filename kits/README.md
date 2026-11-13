# Kits

sbxenv ships one kit, [`config`](config): everything sbxenv adds to Docker's kits. To add a tool or setting, put it in your dotfiles if they can express it, otherwise in `config`. Don't add a kit.

Kits follow the [sandbox kit spec v3](https://github.com/docker/sandbox-kit-spec). For more examples, see the `v3` branch of [docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib/tree/v3).

A kit is a directory with a descriptor, [`config.yaml`](config/config.yaml) (args, capabilities, hooks), and a recipe, [`config.dockerfile`](config/config.dockerfile) (the pinned chezmoi binary).

To try a change, [install from a checkout](../README.md#from-a-checkout) and create a sandbox.

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

- One `ADD --checksum` download per architecture.
- A build stage that only extracts the binary. The version is in the download URL and the checksum pins the bytes, so a wrong pin fails the download.
- A `FROM scratch` overlay of root-owned files, with nothing under `/home` and no `ENTRYPOINT`.
- Release assets that run on the sandbox's Debian trixie: static builds, or glibc builds that need glibc 2.41 or older.

## Hooks and capabilities

- **When:** `install` hooks run once at create. `startup` hooks run on every boot, so they must be idempotent. At create, all `install` hooks run before any `startup` hook.
- **Order:** within a kit, hooks run in list order. Across kits, `requires` and `integrates` run the kits that `provide` the named capability first; `requires` also fails the create when none does. Kits with no such tie run sorted by reference, not in list order.
- **Environment:** a hook sees only the variables in its `env:`, plus `PATH`, `HOME`, `TERM` and a few shell basics.
- **Workspace:** sbx has cloned the workspace when the `install` hooks run, so they can write into it. List `WORKSPACE_DIR` in the hook's `env:`.
- **Late files:** use `startup` to edit files written after the `install` hooks, such as the git config, where sbx then adds `core.excludesFile` and `includeIf`.
- **Shared files:** to share a file with dotfiles or another kit, merge into it from a hook, not with `lifecycle@1` `files`. Set only your own keys, and fill preference keys only when they're missing.
- **Failures:** a failing hook fails the create. If the sandbox works without what the hook does, print what failed and how to redo it, prefixed `<kit> kit:`, and exit 0.

- **Network:** `network-policy@1` `install.allow` hosts are open only while `install` hooks run. `runtime.allow` hosts stay open.

## Versions

- Bump `version` in `config.yaml` on any change to the kit, pin bumps included. A commit `ref=` carries no version, so sbx takes it from the descriptor.
- Docker's kits are pinned by tag in [`sbxenv.example.yaml`](../sbxenv.example.yaml) and [`sbxenv.remote.yaml`](../sbxenv.remote.yaml). Read the comments there before changing one.
- After any bump, recreate your sandboxes as [Upgrade](../docs/sandboxes.md#upgrade) describes.

### Bump a pinned version

To bump chezmoi:

1. In `config.yaml`, change `args.chezmoiVersion.default` and bump `version`.
2. In `config.dockerfile`, change both `--checksum` digests to the `linux-musl_amd64` and `linux_arm64` lines of the release's `chezmoi_<ver>_checksums.txt`. Verify that file first:

   ```sh
   cosign verify-blob --key chezmoi_cosign.pub \
     --bundle chezmoi_<ver>_checksums.txt.sigstore.json chezmoi_<ver>_checksums.txt
   ```

## Publish

Users download `sbxenv.remote.yaml` from `main`. It pins `kits/config` to a full commit SHA in `ref=`: the last commit that changed the kit. A kit change reaches users only when that `ref=` moves.

1. Commit the kit change. `make stale-kits` now fails, because the `ref=` is behind `HEAD`.
2. In a second commit, set the `ref=` to `git log -1 --format=%H -- kits/config`. A commit can't contain its own SHA.
3. Push both commits together. A `ref=` that names an unpushed commit breaks every create from `main`.

Make any change to one env file in the other too. Below the header comments, they differ only in how they name `kits/config`; `make lint` checks this.

A `pre-push` hook that runs `make stale-kits` blocks a push with a stale `ref=`. Install it once per clone:

```sh
printf '#!/bin/sh\nexec make stale-kits\n' > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

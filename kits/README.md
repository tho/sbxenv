# Kits

The kits here follow the [sandbox kit spec v3](https://github.com/docker/sandbox-kit-spec). The `v3` branch of [docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib/tree/v3) has more examples.

A setting that belongs to no single tool doesn't need a new kit. Add it to `kits/config`, or to your dotfiles if they can express it.

## Layout

A kit is a directory with a `<kit>.yaml` descriptor and, usually, a `<kit>.dockerfile` recipe. To try a kit, add its directory to `~/.sbxenv.yaml` by absolute path and create a sandbox.

Start from the kit closest to yours:

| Kit | Shape | Shows |
|---|---|---|
| [`config`](config) | descriptor only | `install` and `startup` hooks, `git-identity@1`, `network-policy@1`, `integrates` |
| [`chezmoi`](chezmoi) | one pinned binary | the minimal recipe |
| [`uv`](uv) | two pinned binaries | shadowing a base-image binary through `PATH` order |
| [`herdr`](herdr) | binary and a script | a create-time arg in argv, a `startup` merge hook, `long-running@1` |
| [`hunk`](hunk) | release archive and a symlink | `agent-skill@1`, an `env:` arg |

## Descriptor

- Write a mixin. A sandbox has exactly one workload, here `docker/sbx-kit-shell`.
- An arg with `buildArg:` is fixed at build, so changing it rebuilds the kit. Args with `env:` or no export resolve at create. Use those for per-sandbox values, such as herdr's `worktreeDir` or hunk's `HUNK_DISABLE_UPDATE_NOTICE`.
- Never interpolate an arg into shell code. Pass it in `env:`, as `kits/config` does, or as its own argv element, as `kits/herdr` does.
- Write each arg's `pattern` for where the value lands, such as a TOML string or a command-line argument.
- Put fixed environment variables in the recipe's `ENV`.
- `requires` and `integrates` both run the named kits' hooks first, and `requires` also fails the composition without them. The names match other kits' `provides`. Hooks with no such dependency run sorted by kit reference, not in list order, so local kits (`/…`) run before `docker.io/…` ones.
- Write `/home/agent` in paths, not `${{ kit.env.HOME }}`.

## Recipe

Copy [`chezmoi.dockerfile`](chezmoi/chezmoi.dockerfile): an `ADD --checksum` download per architecture, a build stage that gates on the exact pinned version, and a `FROM scratch` overlay of root-owned files with nothing under `/home` and no `ENTRYPOINT`. Pick release assets that run on the sandbox's Debian trixie: static builds, or glibc builds that need glibc 2.41 or older.

## Hooks

- `install` hooks run once at create, in dependency order. `startup` hooks run on every boot, so they must be idempotent.
- A hook sees only the variables it lists in `env:`, plus `PATH`, `HOME`, `TERM` and a few shell basics.
- At create, sbx runs the `startup` hooks after all `install` hooks. Use `startup` to edit files that are written late: sbx adds `core.excludesFile` and `includeIf` to the git config after the install hooks, and the dotfiles apply may write herdr's config.
- To share a file with dotfiles or another kit, merge into it from a hook, as `kits/herdr` does, not with `lifecycle@1` `files`. Set only your own keys, and fill preference keys only when they're missing.
- A failing hook fails the create. If the sandbox works without what the hook does, print what failed and how to redo it, prefixed like `herdr kit:`, and carry on.

## Other capabilities

- `network-policy@1`: `install.allow` hosts are open only while install hooks run. `runtime.allow` hosts stay open.
- `agent-skill@1`: the skill appears in every skills directory the agent mixins and `kits/config` declare. Its `path` can't use a create-time arg or `${{ kit.env.* }}`.

## Bump a pinned version

Change `args.version.default` in `<kit>.yaml` and both `--checksum` digests in `<kit>.dockerfile`.

| Kit | Digests from | Provenance check |
|---|---|---|
| chezmoi | `chezmoi_<ver>_checksums.txt` (`linux-musl_amd64`, `linux_arm64`) | `cosign verify-blob --key chezmoi_cosign.pub --bundle chezmoi_<ver>_checksums.txt.sigstore.json chezmoi_<ver>_checksums.txt` |
| hunk | the release's `SHA256SUMS` | `gh attestation verify <asset> -R modem-dev/hunk` |
| uv | the release's `<asset>.sha256` files | `gh attestation verify <asset> -R astral-sh/uv` |
| herdr | GitHub's release asset digests | compare with `https://herdr.dev/latest.json` |

After a herdr bump, if Codex asks to trust herdr's hook again in a new sandbox, copy the new `trusted_hash` for it from that sandbox's `~/.codex/config.toml` into `kits/config/config.yaml`.

After a uv bump, run `uv --version` in a sandbox on Apple silicon.

Bump `kits/config`'s `version` on any change to it. Docker's kits are pinned by tag in [`sbxenv.example.yaml`](../sbxenv.example.yaml) and [`sbxenv.remote.yaml`](../sbxenv.remote.yaml); read the comments there before you change one.

After any bump, recreate your sandboxes as [Upgrade](../docs/sandboxes.md#upgrade) describes.

## Release

`sbxenv.remote.yaml` fetches the kits at the release it names, so a kit change reaches its users only through a new release.

1. Make any change to one env file in the other too. Outside the header comments, they differ only in how they name the local kits, and `make lint` checks that.
2. Set every `ref=` in `sbxenv.remote.yaml` to the new tag, then run `make lint`.
3. Commit, then tag that commit and push both:

   ```sh
   git tag v0.2.0
   git push origin main v0.2.0
   ```

Never move a pushed tag. Users who read a release and pinned its commit, as [Kit sources](../docs/security.md#kit-sources) suggests, would no longer match it.

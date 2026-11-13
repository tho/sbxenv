# sbxenv

An environment file for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`). Install it as `~/.sbxenv.yaml`, and any git repo becomes a sandbox for coding agents:

```sh
cd myrepo && sbx env run
```

Agents work in a private clone of the repo, inside a microVM.

## What's in a sandbox

| Kit | Adds |
|---|---|
| `sbx/shell` | The base sandbox: bash, git, `gh`, Docker and python |
| `sbx/{claude,codex}-mixin` | The `claude` and `codex` agents |
| `sbx/{claude,codex}-sessions` | Keep Claude Code's sessions and memory, and Codex's sessions, on your Mac, per sandbox name, across `sbx env rm` |
| `sbx/cursor-{mixin,sessions}` | The `cursor-agent` agent and its chats, commented out |
| [`kits/config`](kits/config) | Your git identity, and your dotfiles applied with [chezmoi](https://chezmoi.io) at create |

Remove any kit but `sbx/shell` from `~/.sbxenv.yaml` if you don't want it.

## Requirements

- macOS with [sbx](https://docs.docker.com/ai/sandboxes/) 0.53.0 or later, signed in with `sbx login`.
- A way to build `kits/config` at create: `export SBX_KIT_BUILDER=sandbox` in your shell profile, which builds it in a sandbox, or Docker Desktop running.

## Install

Install from GitHub, or from a checkout if you want to change the kit. Both write `~/.sbxenv.yaml`.

### Without a checkout

Download `sbxenv.remote.yaml`. It pins `kits/config` to a commit of this repo on GitHub:

```sh
curl -fsSL -o ~/.sbxenv.yaml https://raw.githubusercontent.com/tho/sbxenv/main/sbxenv.remote.yaml
```

sbx installs kits only from `docker.io/` until you allow other sources. Allow this repo's owner once:

```sh
sbx settings set kit.allowedSources '["docker.io/","github.com/tho/"]'
```

Read [Kit sources](docs/security.md#kit-sources) for what that allows.

### From a checkout

Clone the repo and point `~/.sbxenv.yaml` at its kit:

```sh
git clone https://github.com/tho/sbxenv && cd sbxenv
sed "s|/path/to/sbxenv|$PWD|" sbxenv.example.yaml > ~/.sbxenv.yaml
```

sbx builds `kits/config` from the checkout at create, so your changes take effect in the next sandbox you create.

### Secrets

Store a secret for each agent you use:

| Agent | Command |
|---|---|
| Claude Code | `sbx secret set anthropic` (API key); `/login` inside Claude Code for OAuth ([details](https://docs.docker.com/ai/sandboxes/agents/claude-code/#authentication)) |
| Codex | `sbx secret set openai [--oauth]` ([details](https://docs.docker.com/ai/sandboxes/agents/codex/#authentication)) |
| Cursor | `sbx secret set cursor` (API key), or sign in on first run ([details](https://docs.docker.com/ai/sandboxes/agents/cursor/#authentication)) |

For `gh` and `git push` in the sandbox, also store your `gh` token. Agents in every sandbox get the token's full reach, so read [Credentials](docs/security.md#credentials) first:

```sh
sbx secret set github --command 'gh auth token'
```

## Run an agent

Run `sbx env run` from the repo's main host checkout, not from a git worktree.

Answer the first run's approval prompt yourself. With `--force` or `--detach`, sbx creates the sandbox without the credentials.

You get a bash shell in the clone, at the same path as your checkout. Start an agent there:

```sh
claude    # or codex
```

## Get the work back

The sandbox is named `shell-<repo directory>`. While it runs, your host checkout has a `sandbox-<name>` remote. Fetch a branch and review it as usual:

```sh
git fetch sandbox-shell-myrepo
git diff main...refs/sandboxes/shell-myrepo/feat-x
git branch feat-x refs/sandboxes/shell-myrepo/feat-x
```

Before you build the branch or open it in an editor, read [Fetched branches](docs/security.md#fetched-branches).

The sandbox stops 30 seconds after its last session disconnects, such as when you exit the `sbx env run` shell, and its agents stop with it. `sbx stop shell-myrepo` stops it at once. The remote exists only while the sandbox runs; fetched branches stay under `refs/sandboxes/`.

## Documentation

- [Sandboxes](docs/sandboxes.md): names, the clone, disks, GitHub, recreating, upgrading
- [Dotfiles](docs/dotfiles.md): apply your chezmoi repo in every new sandbox, and allow the hosts it needs
- [Security](docs/security.md): what agents can read and reach, fetched branches, a repo's own `sbxenv.yaml`
- [Kits](kits/README.md): change the kit, bump a pin, publish

## License

[The Unlicense](LICENSE): public domain. The tools the kits download keep their own licenses.

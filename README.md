# sbxenv

An environment file for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`). Install it as `~/.sbxenv.yaml`, and any git repo becomes a sandbox for coding agents:

```sh
cd myrepo && sbx env run
```

Agents work in a private clone of the repo, inside a microVM.

## What's in a sandbox

| Kit | Adds |
|---|---|
| `docker/sbx-kit-shell` | The base sandbox: bash, git, `gh`, node and python |
| `docker/sbx-kit-{claude,codex}-mixin`, `sbx/copilot-mixin` | `claude`, `codex` and `copilot` agents |
| `sbx/cursor-mixin` | The `cursor-agent` agent. Commented out; uncomment to add it |
| [`kits/config`](kits/config) | Git identity and other cross-cutting setup |
| [`kits/chezmoi`](kits/chezmoi) | [chezmoi](https://chezmoi.io), and your dotfiles applied at create |
| [`kits/uv`](kits/uv) | [uv](https://docs.astral.sh/uv/), because the base image's uv crashes on Apple silicon |
| [`kits/rsync`](kits/rsync) | rsync, for [`scripts/sbx-state-sync.sh`](scripts/sbx-state-sync.sh), which carries agent sessions and memory between sandbox and host |

You can drop any kits you do not want or need from `~/.sbxenv.yaml`.

## Requirements

- macOS with [sbx](https://docs.docker.com/ai/sandboxes/) 0.50.1 or later, signed in with `sbx login`.
- Docker Desktop, running whenever you create a sandbox from a checkout.

## Install

Install either from GitHub, which needs no checkout, or a checkout, which lets you change the kits. Both write `~/.sbxenv.yaml`.

### Without a checkout

Download `sbxenv.remote.yaml`. It pins each kit to a commit of this repo on GitHub:

```sh
curl -fsSL -o ~/.sbxenv.yaml https://raw.githubusercontent.com/tho/sbxenv/main/sbxenv.remote.yaml
```

sbx installs kits only from `docker.io/` until you allow other sources. Allow this repo's owner once.

```sh
sbx settings set kit.allowedSources '["docker.io/","github.com/tho/"]'
```

Read [Kit sources](docs/security.md#kit-sources) for what that allows.

### From a checkout

Clone the repo and point `~/.sbxenv.yaml` at its kits:

```sh
git clone https://github.com/tho/sbxenv && cd sbxenv
sed "s|/path/to/sbxenv|$PWD|" sbxenv.example.yaml > ~/.sbxenv.yaml
```

sbx builds the kits from the checkout as it is at create, so your changes to them take effect in the next sandbox you create.

### Secrets

Store a secret for each agent you use:

| Agent | Command |
|---|---|
| Claude Code | `sbx secret set anthropic` (API key); `/login` inside Claude Code for OAuth ([details](https://docs.docker.com/ai/sandboxes/agents/claude-code/#authentication)) |
| Codex | `sbx secret set openai [--oauth]` ([details](https://docs.docker.com/ai/sandboxes/agents/codex/#authentication)) |
| Copilot | `sbx secret set copilot`, with a fine-grained PAT that has "Copilot Requests" ([details](https://docs.docker.com/ai/sandboxes/agents/copilot/#authentication))|
| Cursor | `sbx secret set cursor`, with an API key or interactively on first run ([details](https://docs.docker.com/ai/sandboxes/agents/cursor/#authentication))|

Without the `copilot` secret, Copilot uses the `github` secret.

For `gh` and git in the sandbox, also store your `gh` token. It gives the agents in every sandbox the token's full reach, so read [Credentials](docs/security.md#credentials) first:

```sh
sbx secret set github --command 'gh auth token'
```

## Run an agent

Run `sbx env run` from the repo's main host checkout, not from a git worktree.

Answer the first run's approval prompt yourself. With `--force` or `--detach`, sbx creates the sandbox without the credentials.

You get a bash shell in the clone, at the same path as your checkout. Start an agent there:

```sh
claude    # or codex, copilot
```

## Get the work back

The sandbox is named after the repo's directory. While it runs, your host checkout has a remote for it. Fetch a branch and review it as usual.

```sh
git fetch sandbox-sbx-kit-shell-myrepo
git diff main...refs/sandboxes/sbx-kit-shell-myrepo/feat-x
git branch feat-x refs/sandboxes/sbx-kit-shell-myrepo/feat-x
```

Before you build the branch or open it in an editor, read [Fetched branches](docs/security.md#fetched-branches).

The sandbox stops 30 seconds after its last session, such as your `sbx env run` shell, disconnects, and agents running in it stop too. `sbx stop sbx-kit-shell-myrepo` stops it sooner. A stop removes the remote. The remote will be re-created and updated when the sandbox is running.

## Documentation

- [Sandboxes](docs/sandboxes.md): names, the clone, disks, GitHub, recreating, upgrading
- [Dotfiles](docs/dotfiles.md): apply your chezmoi repo in every new sandbox
- [State sync](docs/state-sync.md): carry Claude Code sessions and memory between a sandbox and your Mac
- [Security](docs/security.md): what agents can read and reach, fetched branches and a repo's own `sbxenv.yaml`
- [Troubleshooting](docs/troubleshooting.md): error messages and their fixes
- [Kits](kits/README.md): write a kit or bump a pinned version

## License

[The Unlicense](LICENSE): public domain. The tools the kits download keep their own licenses.

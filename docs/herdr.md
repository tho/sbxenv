# Herdr

[Herdr](https://herdr.dev) is a terminal workspace manager for coding agents. On your Mac, it connects to each sandbox's herdr server over SSH.

## Setup

Install Herdr on the Mac and pin it:

```sh
brew install herdr
```

Herdr must speak the same protocol as the herdr server that [`kits/herdr`](../kits/herdr/herdr.yaml) pins.

Once per Mac, make the sandboxes reachable over SSH as `<name>.sbx`:

```sh
sbx setup ssh
```

Then add each sandbox as a machine:

```sh
herdr machine add sbx-kit-shell-myrepo.sbx --label myrepo
```

The label is the name you pass to `herdr --machine`. Don't add a user to the SSH target. `herdr machine add` should reuse the kit's herdr. If it offers to install one instead, the Mac's Herdr doesn't match the kit's protocol, or `HERDR_REMOTE_BINARY` is set.

## After a stop

Reconnect the machine from the Herdr sidebar. That starts the sandbox and its herdr server, which restores the layout. Agent panes started in Herdr resume their conversations.

## After a recreate

Herdr's connection fails with `sandbox identity changed`. Close its old SSH master, then reconnect from the sidebar:

```sh
t=sbx-kit-shell-myrepo.sbx
h=$(printf '%s\0%s' "$HOME/.config/herdr/config.toml" "$t" | shasum -a 256 | cut -c1-24)
for s in /tmp/hssh-$(id -u)/$h-*; do ssh -O exit -S "$s" "$t"; done
```

## Config in the sandbox

On every start, the herdr kit sets these keys in the sandbox's `~/.config/herdr/config.toml` and keeps the rest of the file:

- `version_check` and `manifest_check` in `[update]` to `false`
- `directory` in `[worktrees]` to the kit's `worktreeDir` arg, which the env files set to `<clone>/.worktrees`
- `default_shell` in `[terminal]` to `/bin/bash`, only if the file doesn't set one

If your dotfiles set anything in those three tables, write them with `[table]` headers, not dotted keys or inline tables. Otherwise the merge fails, leaves the file unchanged and prints `herdr kit: config merge failed`.

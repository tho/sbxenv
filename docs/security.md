# Security

## Your checkout

Agents can't change your checkout or its `.git`, but they can read all of it at `/run/sandbox/source`.

## Credentials

Your `gh` token never enters the sandbox. The sbx proxy injects it into requests, and `GH_TOKEN` inside is a placeholder.

The `github` secret still has the token's full reach, and secrets are global by default. So the agents in every sandbox can act on every repo you can, workflows included. For less reach, store a fine-grained PAT with `sbx secret set github`, or scope the secret to one sandbox with `--sandbox <name>`.

## Network

A sandbox can reach the hosts in your global sbx policy, plus the hosts its kits allow. Every process in the sandbox has that reach, not just the agents. The proxy adds a kit's credential to any request for that credential's hosts, whichever process sends it.

## Kit sources

A kit's hooks run in every sandbox that uses it, with the agents' network reach and credentials. `kit.allowedSources` is the list of places sbx installs kits from. Adding `github.com/tho/` lets any sbxenv file you run, including [a repo's own](#a-repos-own-sbxenvyaml), use a kit from any repo under that GitHub account, at any ref.

`ref=v0.1.2` names a git tag, and whoever controls the repo can move a tag. To pin the exact code you read, replace the tag in each `ref=` with the release's commit SHA.

## Fetched branches

An agent's branch can change `sbxenv.yaml`, `.claude/`, `.hunk/`, `.vscode/`, `.envrc` and build scripts. Read it like a stranger's pull request before you build it, run it, or open it in an editor or a host agent. `hunk diff main...<branch>` runs nothing from it as long as you haven't checked it out.

## A repo's own sbxenv.yaml

If a repo has its own `sbxenv.yaml`, `sbx env run` merges it over your `~/.sbxenv.yaml`. That file can add host commands, mounts and kits. In a repo you don't trust, check for it, read `sbx env plan`, and never use `--force`.

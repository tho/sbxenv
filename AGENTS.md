# AGENTS.md

- Read [kits/README.md](kits/README.md) before editing or bumping a kit.
- Use the plain sbx/herdr CLIs, no wrappers. Before adding a kit, file or arg, check that sbx or the base image doesn't already provide it.
- Settle facts from upstream source, not prose or memory: sandbox-kit-spec's `spec/` and `resolve/` for sbx, herdr's source at the pinned tag. Validate descriptors with the `spec` package (`sbx kit validate --offline` rejects v3 source kits).
- The agent shell can't reach the Docker or sbx sockets. To test a create, write `.git/e2e-test.sh` around `sbx env run --force --detach` and ask the user to run `! bash <absolute path>`. Only a fresh create with the user's real dotfiles, then a stop/start, proves a hook.
- Commit nothing personal (names, emails, `/Users/…`). After changing `sbxenv.example.yaml`, remind the user to update `~/.sbxenv.yaml` by hand. Run `make lint` before committing.

# Dotfiles

Set the `dotfiles` arg of the `kits/config` entry in `~/.sbxenv.yaml` to your dotfiles repo, such as `you/dotfiles`, and keep `kits/chezmoi` in the file. Each new sandbox then runs `chezmoi init --apply` on that repo.

The value can be an `https://` URL or a shorthand that chezmoi expands to one: `user`, `user/repo`, `sr.ht/~user[/repo]`, or `site/user[/repo]` such as `gitlab.com/user/repo`.

During the apply, the sandbox can reach GitHub, `deb.debian.org` and PyPI. Any other forge or host your dotfiles download from has to be in your global sbx policy.

## Writing dotfiles for the sandbox

- The apply is unattended (`--promptDefaults`), so every prompt in `.chezmoi.toml.tmpl` needs a default.
- Your git identity is set before the apply, so prompts can default to `git config --global user.name` and `user.email`.
- The agent mixins write their settings before the apply. Merge your settings into them with `modify_` scripts.
- Scripts that install herdr, hunk or uv should skip the install when the tool is already on `PATH`.
- If you manage `~/.config/herdr/config.toml`, see what the herdr kit [sets in it](herdr.md#config-in-the-sandbox).

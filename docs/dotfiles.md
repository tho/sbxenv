# Dotfiles

Set the `dotfiles` arg of the `kits/chezmoi` entry in `~/.sbxenv.yaml` to your dotfiles repo, such as `you/dotfiles`. Each new sandbox then runs `chezmoi init --apply` on that repo.

The value can be an `https://` URL or a shorthand that chezmoi expands to one: `user`, `user/repo`, `sr.ht/~user[/repo]`, or `site/user[/repo]` such as `gitlab.com/user/repo`.

During the apply, the sandbox can reach GitHub, `deb.debian.org` and PyPI. Any other forge or host your dotfiles download from has to be in your global sbx policy.

## Writing dotfiles for the sandbox

- The apply is unattended (`--promptDefaults`), so every prompt in `.chezmoi.toml.tmpl` needs a default.
- Your git identity is set before the apply, so prompts can default to `git config --global user.name` and `user.email`.
- The agent mixins write their settings before the apply. Merge your settings into them with `modify_` scripts.
- The apply runs from `$HOME`, before sbx clones the workspace. On every boot, the kit reruns your scripts, not your files, from the workspace with `chezmoi apply --include=scripts`, so `.chezmoi.commandDir` is the workspace. Write project-level config, such as `.claude/settings.local.json`, from a `run_` script that is safe to repeat. The rerun reaches only hosts in your runtime policy.
- Scripts that install tools a kit may already provide, such as uv, should skip the install when the tool is already on `PATH`.

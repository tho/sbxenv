# Dotfiles

Set the `dotfiles` arg of the `kits/config` entry in `~/.sbxenv.yaml` to your dotfiles repo, such as `you/dotfiles`. Each new sandbox then runs `chezmoi init --apply` on that repo.

The value can be an `https://` URL or a shorthand that chezmoi expands to one: `user`, `user/repo`, `sr.ht/~user[/repo]`, or `site/user[/repo]` such as `gitlab.com/user/repo`.

During the apply, the sandbox can reach GitHub. The apt sources, `deb.debian.org` and `dhi.io`, are always open. For another forge, or a host your dotfiles download from, [allow it](#allow-more-hosts).

## Allow more hosts

`~/.sbxenv.yaml` has no field for hosts, so allow them in a kit of your own:

1. Create a directory outside any repo, such as `~/.config/sbxenv/egress`, with this `egress.yaml` in it. The file name must match the directory name.

   ```yaml
   # syntax=docker/sandbox-kit:3
   schemaVersion: "3"
   displayName: My egress
   description: Hosts my dotfiles and tools need
   kind: mixin
   # Bump on any change, so `sbx env plan` shows the kit as changed.
   version: "1.0.0"
   capabilities:
     - type: com.docker.sandbox/network-policy@1
       config:
         # Open only while install hooks run, such as the dotfiles apply.
         install:
           allow:
             - example.dev
         # Open while the sandbox runs, such as for a tool's self-update.
         runtime:
           allow:
             - example.dev
   ```

2. Replace `example.dev` with your hosts. Patterns such as `*.example.dev` and `example.dev:443` also work. Drop the `runtime` block if the tools need the hosts only to install.
3. In `~/.sbxenv.yaml`, uncomment the `/absolute/path/to/egress` entry under `kits:` and set it to the directory's absolute path. sbx doesn't expand `~`.
4. Create a new sandbox. Existing sandboxes keep their allow lists until you [recreate](sandboxes.md#recreate) them.

To allow a host without a kit, run `sbx policy allow network <host>`. That applies to every sandbox; add `--sandbox <name>` for one running sandbox.

## Writing dotfiles for the sandbox

- The apply is unattended (`--promptDefaults`), so every prompt in `.chezmoi.toml.tmpl` needs a default.
- Your git identity is set before the apply, so prompts can default to `git config --global user.name` and `user.email`.
- The agent mixins write their settings before the apply. Merge your settings into them with `modify_` scripts.
- Don't manage the directories that the [session kits](sandboxes.md#recreate) keep on the host. They are symlinks, and a create fails when one is already a nonempty directory.
- The apply runs once, at create, from the workspace clone, so `.chezmoi.commandDir` is the workspace. Write project-level config, such as `.claude/settings.local.json`, from a script. Nothing reruns on later boots; run `chezmoi apply` in the sandbox yourself.
- The base image's `/usr/bin/uv` aborts on Apple silicon with `<jemalloc>: Unsupported system page size`. If you need uv, install Astral's release from your dotfiles, ahead of `/usr/bin` on `PATH`.

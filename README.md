# rhel-setup

One-shot setup for a RHEL 10 workstation, reconstructed from my actual machine
(installed packages, flatpaks, enabled services, shell history).

## Usage

On a freshly installed, subscription-registered RHEL 10 system:

```sh
./setup.sh
```

Safe to re-run — every step skips what's already present, and packages that
may not exist for el10 are installed best-effort.

## What it does

- **Repos**: EPEL + CRB, Docker CE, GitHub CLI, Google Cloud CLI, Chrome,
  MongoDB 8.0 (el9 repo — no el10 packages yet), VS Code, Sublime, TablePlus,
  Beyond Compare 5, Flathub
- **Docker**: removes the podman stack, installs Docker CE + compose/buildx,
  enables the service, adds user to the `docker` group
- **CLI tooling**: build toolchain, python/pipx/uv, go, rust/cargo, fzf,
  ripgrep, bat, fd, btop, just, yq, mongosh + mongo tools, gcloud, kubectl,
  helm, opentofu, pandoc/texlive, hardware & monitoring utils
- **Cargo tools** (not packaged for el10): eza, dust, zoxide, tealdeer, hyperfine
- **git-delta** binary into `~/.local/bin`
- **fnm** + Node 26 (default)
- **Desktop apps**: kitty, VS Code, Sublime Text/Merge, Beyond Compare,
  TablePlus, Chrome stable+beta, GNOME tweaks/extensions, LibreOffice
- **Flatpaks**: Obsidian, Slack, Zoom, Postman, Compass, DbGate, RedisInsight,
  DBeaver, Meld, Mission Center, Remmina, OnlyOffice
- **Virtualization**: qemu-kvm/libvirt/virt-manager, user in `libvirt` group
- **Cockpit** + PCP monitoring, sysstat, tuned
- **Fonts**: Noto/Liberation/DejaVu/JetBrains Mono/Inter rpms + CascadiaCode
  and JetBrainsMono Nerd Fonts
- **Shell**: zsh as login shell, liquidprompt + antidote into `~/sh`,
  clones [rcfiles](https://github.com/chaudhryjunaid/rcfiles) into `~/setup`
- **Home skeleton**: `can work personal projects backups archive inbox homelab data`
- **Work repos** via `gh` (if authenticated)
- **Standalone installers**: Claude Code, Zed
- **GNOME**: kitty as default terminal, dash-to-dock + appindicator enabled

## After running

1. `cd ~/setup/rcfiles && ./configure.sh && ./setup-git-identity.sh`
2. Log out/in (zsh, docker/libvirt groups, fonts)
3. `gh auth login`, then re-run to clone work repos
4. `gcloud init && gcloud auth application-default login`
5. WebStorm: extract JetBrains tarball to `~/.local/webstorm`

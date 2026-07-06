#!/bin/bash

# setup.sh — configure a pristine RHEL 10 workstation like this one.
#
# Reconstructed from the actual state of this machine (dnf userinstalled,
# flatpak list, enabled services, ~/.zsh_history). Safe to re-run: every step
# skips what is already present, and optional packages are best-effort.
#
# Prerequisites:
#   - RHEL 10 with an active subscription (subscription-manager register)
#   - Run as your normal user (uses sudo where needed), from a terminal
#
# After this, from ~/setup/rcfiles:
#   ./configure.sh && ./setup-git-identity.sh
# then log out/in to pick up zsh, docker/libvirt groups, and fonts.

set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    WARN: %s\033[0m\n' "$*" >&2; }

# Install packages best-effort, one at a time, so a missing package
# (repo drift, not-yet-packaged-for-el10) doesn't abort the run.
dnf_opt() {
    local pkg
    for pkg in "$@"; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            continue
        fi
        if $SUDO dnf install -y "$pkg" >/dev/null 2>&1; then
            echo "    installed: $pkg"
        else
            warn "'$pkg' unavailable — install manually if you want it"
        fi
    done
}

# ---------------------------------------------------------------------------
log "Checking subscription status"
if ! $SUDO subscription-manager status >/dev/null 2>&1; then
    warn "System does not appear to be registered; run 'sudo subscription-manager register' first."
    warn "Continuing anyway — RHEL repos may fail."
fi

# ---------------------------------------------------------------------------
log "Enabling repositories"

# EPEL needs CRB (CodeReady Builder) for many of its dependencies.
$SUDO subscription-manager repos --enable "codeready-builder-for-rhel-10-$(arch)-rpms" 2>/dev/null \
    || $SUDO dnf config-manager --set-enabled crb 2>/dev/null \
    || warn "could not enable CRB repo"
dnf_opt epel-release dnf-plugins-core

add_repo() {  # add_repo <name> <heredoc on stdin>
    local file="/etc/yum.repos.d/$1.repo"
    if [ -f "$file" ]; then
        echo "    repo exists: $1"
    else
        $SUDO tee "$file" >/dev/null
        echo "    repo added: $1"
    fi
}

add_repo docker-ce <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/rhel/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/rhel/gpg
EOF

add_repo gh-cli <<'EOF'
[gh-cli]
name=packages for the GitHub CLI
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.asc
EOF

add_repo google-cloud-sdk <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg
EOF

add_repo google-chrome <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

# NOTE: MongoDB does not publish el10 packages yet; the redhat/9 repo works on RHEL 10.
add_repo mongodb-org-8.0 <<'EOF'
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF

add_repo vscode <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

add_repo sublime-text <<'EOF'
[sublime-text]
name=Sublime Text - x86_64 - stable
baseurl=https://download.sublimetext.com/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://download.sublimetext.com/sublimehq-rpm-pub.gpg
EOF

add_repo tableplus <<'EOF'
[tableplus]
name=TablePlus - x86_64 - Stable
baseurl=https://yum.tableplus.com/rpm/x86_64
enabled=1
gpgcheck=1
gpgkey=https://yum.tableplus.com/apt.tableplus.com.gpg.key
EOF

add_repo scootersoftware <<'EOF'
[scootersoftware]
name=Scooter Software
baseurl=https://www.scootersoftware.com/rpm/bcompare5
enabled=1
gpgcheck=1
gpgkey=https://www.scootersoftware.com/RPM-GPG-KEY-scootersoftware
EOF

$SUDO dnf makecache >/dev/null

# ---------------------------------------------------------------------------
log "Installing Workstation environment group"
$SUDO dnf group install -y Workstation >/dev/null 2>&1 || warn "Workstation group install failed"

# ---------------------------------------------------------------------------
log "Replacing podman stack with Docker CE"
if ! command -v docker >/dev/null 2>&1; then
    systemctl --user stop podman.socket podman.service 2>/dev/null || true
    $SUDO systemctl stop podman.socket podman.service 2>/dev/null || true
    $SUDO dnf remove -y podman podman-docker podman-plugins podman-compose buildah skopeo >/dev/null 2>&1 || true
    $SUDO dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
$SUDO systemctl enable --now docker
$SUDO groupadd -f docker
$SUDO usermod -aG docker "$USER"

# ---------------------------------------------------------------------------
log "Installing CLI tooling (dnf)"

# Shell, editors, VCS
dnf_opt zsh git gh tig vim-enhanced neovim emacs tmux screen

# Build toolchain
dnf_opt gcc gcc-c++ make cmake ninja-build pkgconf-pkg-config autoconf automake \
    libtool patch diffutils elfutils binutils perf shellcheck ShellCheck editorconfig

# Languages & package managers
dnf_opt python3 python3-pip pipx uv golang rust cargo libxcrypt-compat

# Modern CLI replacements & utilities
dnf_opt fzf ripgrep bat fd-find duf htop btop ncdu cloc just yq jq aria2 \
    tldr cheat hyperfine socat mtr nethogs iftop iotop-c

# Archive / transfer
dnf_opt rsync tar zip unzip xz zstd curl wget openssh-clients rclone restic borgbackup

# Databases (clients only — servers run in containers)
dnf_opt sqlite mongodb-mongosh mongodb-database-tools mongodb-org-tools \
    mongodb-org-database-tools-extra

# Cloud & k8s (kubectl comes from the Google Cloud repo, helm/opentofu from EPEL)
dnf_opt google-cloud-cli kubectl helm opentofu

# Docs & media
dnf_opt pandoc texlive poppler-utils ImageMagick asciinema qrencode

# Hardware / monitoring / power
dnf_opt sysstat smartmontools nvme-cli lm_sensors powertop tuned kernel-tools \
    ethtool pciutils usbutils dmidecode lshw wireshark nmap audit

# ---------------------------------------------------------------------------
log "Installing desktop apps (dnf)"
dnf_opt kitty code sublime-text sublime-merge bcompare tableplus \
    google-chrome-stable google-chrome-beta \
    gnome-tweaks gnome-extensions-app gnome-shell-extension-appindicator \
    gnome-shell-extension-dash-to-dock gnome-shell-extension-system-monitor \
    gnome-browser-connector gnome-disk-utility gnome-system-monitor \
    gnome-text-editor gedit dconf-editor seahorse firewall-config evince
dnf_opt libreoffice libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw

# ---------------------------------------------------------------------------
log "Installing fonts"
dnf_opt google-noto-fonts-common google-noto-sans-fonts google-noto-serif-fonts \
    google-noto-emoji-fonts liberation-fonts dejavu-sans-fonts dejavu-serif-fonts \
    jetbrains-mono-fonts rsms-inter-fonts

FONT_DIR="$HOME/.local/share/fonts"
NERD_BASE="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
fonts_changed=0
for font in CascadiaCode JetBrainsMono; do
    dest="$FONT_DIR/${font}Nerd"
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        continue
    fi
    log "Installing $font Nerd Font"
    mkdir -p "$dest"
    tmpzip=$(mktemp --suffix=.zip)
    curl -fsSL -o "$tmpzip" "$NERD_BASE/$font.zip"
    unzip -o "$tmpzip" -d "$dest" >/dev/null
    rm -f "$tmpzip"
    fonts_changed=1
done
[ "$fonts_changed" -eq 1 ] && fc-cache -f "$FONT_DIR" >/dev/null

# ---------------------------------------------------------------------------
log "Installing virtualization stack (KVM/libvirt)"
dnf_opt qemu-kvm libvirt libvirt-client virt-install virt-viewer virt-manager \
    virt-top edk2-ovmf swtpm guestfs-tools libosinfo bridge-utils virtio-win
$SUDO systemctl enable --now libvirtd 2>/dev/null || warn "could not enable libvirtd"
$SUDO usermod -aG libvirt "$USER" 2>/dev/null || true

# ---------------------------------------------------------------------------
log "Enabling Cockpit and monitoring services"
$SUDO systemctl enable --now cockpit.socket 2>/dev/null || warn "could not enable cockpit"
dnf_opt pcp cockpit-pcp
$SUDO systemctl enable --now pmcd 2>/dev/null || true
$SUDO systemctl enable --now sysstat lm_sensors tuned 2>/dev/null || true

# ---------------------------------------------------------------------------
log "Installing Flatpaks"
if command -v flatpak >/dev/null 2>&1; then
    $SUDO flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y --noninteractive flathub \
        md.obsidian.Obsidian \
        com.slack.Slack \
        us.zoom.Zoom \
        com.getpostman.Postman \
        com.mongodb.Compass \
        org.dbgate.DbGate \
        com.redis.RedisInsight \
        io.dbeaver.DBeaverCommunity \
        org.gnome.meld \
        org.gnome.Evince \
        io.missioncenter.MissionCenter \
        org.remmina.Remmina \
        org.onlyoffice.desktopeditors \
        || warn "some flatpaks failed to install"
else
    warn "flatpak not found — skipping flatpak apps"
fi

# ---------------------------------------------------------------------------
log "Installing cargo tools (not packaged for el10)"
export PATH="$HOME/.cargo/bin:$PATH"
for crate in eza du-dust zoxide tealdeer hyperfine; do
    bin="${crate/du-dust/dust}"; bin="${bin/tealdeer/tldr}"
    command -v "$bin" >/dev/null 2>&1 || cargo install "$crate"
done

# ---------------------------------------------------------------------------
log "Installing git-delta"
if ! command -v delta >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    DELTA_VER="0.19.2"
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/delta.tar.gz" \
        "https://github.com/dandavison/delta/releases/download/${DELTA_VER}/delta-${DELTA_VER}-x86_64-unknown-linux-gnu.tar.gz"
    tar -xzf "$tmpdir/delta.tar.gz" -C "$tmpdir"
    cp "$tmpdir/delta-${DELTA_VER}-x86_64-unknown-linux-gnu/delta" "$HOME/.local/bin/"
    rm -rf "$tmpdir"
fi

# ---------------------------------------------------------------------------
log "Installing fnm + Node 26"
if ! command -v fnm >/dev/null 2>&1 && [ ! -d "$HOME/.local/share/fnm" ]; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi
export PATH="$HOME/.local/share/fnm:$PATH"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)" || true
    fnm list 2>/dev/null | grep -q v26 || fnm install 26
    fnm default 26 || true
fi

# ---------------------------------------------------------------------------
log "Setting up shell environment (zsh, liquidprompt, antidote, dotfiles)"
mkdir -p "$HOME/sh" "$HOME/setup"
[ -d "$HOME/sh/liquidprompt" ] \
    || git clone --branch stable https://github.com/liquidprompt/liquidprompt.git "$HOME/sh/liquidprompt"
[ -d "$HOME/sh/antidote" ] \
    || git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/sh/antidote"
[ -d "$HOME/setup/rcfiles" ] \
    || git clone git@github.com:chaudhryjunaid/rcfiles.git "$HOME/setup/rcfiles" \
    || warn "could not clone rcfiles (SSH key not set up yet?)"

ZSH_BIN="$(command -v zsh || true)"
if [ -n "$ZSH_BIN" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_BIN" ]; then
    $SUDO chsh -s "$ZSH_BIN" "$USER" || warn "could not change shell; run: chsh -s $ZSH_BIN"
fi

# ---------------------------------------------------------------------------
log "Creating home directory skeleton"
mkdir -p "$HOME"/{can,work,personal,projects,backups,archive,inbox,homelab,data}

# ---------------------------------------------------------------------------
log "Cloning work/homelab repos (needs 'gh auth login')"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    clone() { [ -d "$2" ] || gh repo clone "$1" "$2" || warn "clone failed: $1"; }
    clone CANmobilities/CAN-Go_backend   "$HOME/can/CAN-Go_backend"
    clone CANmobilities/can.portal       "$HOME/can/can.portal"
    clone CANmobilities/can-care-kfsh-app "$HOME/can/can-care-kfsh-app"
    clone chaudhryjunaid/unixlab         "$HOME/homelab/unixlab"
else
    warn "gh not authenticated — run 'gh auth login' then re-run, or clone repos manually"
fi

# ---------------------------------------------------------------------------
log "Installing standalone tools (Claude Code, Zed)"
command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
command -v zed    >/dev/null 2>&1 || curl -fsSL https://zed.dev/install.sh | sh

# ---------------------------------------------------------------------------
log "Applying GNOME settings"
if command -v gsettings >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty' 2>/dev/null || true
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '' 2>/dev/null || true
    for ext in dash-to-dock@micxgx.gmail.com appindicatorsupport@rgcjonas.gmail.com; do
        gnome-extensions enable "$ext" 2>/dev/null || true
    done
else
    warn "no GNOME session — skipping gsettings (re-run from a desktop terminal)"
fi

# ---------------------------------------------------------------------------
log "Updating system"
$SUDO dnf update -y --refresh >/dev/null 2>&1 || warn "dnf update failed"

# ---------------------------------------------------------------------------
cat <<'NOTE'

Done. Manual follow-ups:
  1. cd ~/setup/rcfiles && ./configure.sh && ./setup-git-identity.sh
  2. Log out/in — picks up zsh, docker & libvirt groups, fonts.
  3. gh auth login            (then re-run this script to clone work repos)
  4. gcloud init && gcloud auth application-default login
  5. claude mcp add --scope user gcloud -- npx -y @google-cloud/gcloud-mcp
  6. WebStorm: download tarball from jetbrains.com, extract to ~/.local/webstorm
     (PATH is already handled by ~/.zshrc from rcfiles).
  7. GNOME extensions from extensions.gnome.org: Astra Monitor.
  8. Set terminal font to "CaskaydiaCove Nerd Font" or "JetBrainsMono Nerd Font".
  9. Not installed (unavailable on el10 at setup time): ffmpeg (needs RPM Fusion),
     k9s/kubectx/minikube/skaffold, redis CLI, shfmt, pre-commit, PowerShell, ghostty.
NOTE

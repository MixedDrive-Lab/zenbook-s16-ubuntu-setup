#!/usr/bin/env bash
# ============================================================================
# Section 05 — Dev toolchain (mise + Docker)
#
# mise: single binary version manager for multiple languages (Python, Node,
#       Rust, Go, Ruby, Java, ...). Replaces nvm/pyenv/rbenv/asdf.
# Docker: official Docker CE + Compose v2 plugin + buildx.
#
# This section installs only the runtime; per-language tools are NOT
# auto-installed — see docs/04-dev-toolchain.md for `mise use` examples.
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_05_dev_toolchain() {
    log "=== Section 05: Dev toolchain (mise + Docker) ==="

    _install_mise
    _install_docker

    success "Section 05 complete"
}

_install_mise() {
    if command -v mise &>/dev/null; then
        success "mise already installed: $(mise --version 2>&1 | head -1)"
    else
        log "Adding mise APT repo..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] add mise apt repo + install mise"
        else
            sudo install -dm 755 /etc/apt/keyrings
            curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor \
                | sudo tee /etc/apt/keyrings/mise-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" \
                | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
            sudo apt update >>"$LOG_FILE" 2>&1
            sudo apt install -y mise >>"$LOG_FILE" 2>&1 || {
                error "mise install failed"
                return 1
            }
            success "mise installed"
        fi
    fi

    # Activate mise in bashrc (idempotent)
    if [[ "$DRY_RUN" != "true" ]] && [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q 'mise activate bash' "$HOME/.bashrc"; then
            echo 'eval "$(mise activate bash)"' >> "$HOME/.bashrc"
            success "Added mise activation to ~/.bashrc"
        else
            success "mise activation already in ~/.bashrc"
        fi
    fi

    # Default global config — empty, user opts in to languages
    if [[ "$DRY_RUN" != "true" ]] && [[ ! -f "$HOME/.config/mise/config.toml" ]]; then
        ensure_dir "$HOME/.config/mise"
        cat > "$HOME/.config/mise/config.toml" <<'EOF'
# mise global config — installed by zenbook-s16-ubuntu-setup
# Add languages with: mise use --global <tool>@<version>
# Example:
#   mise use --global python@3.12
#   mise use --global node@lts
#   mise use --global rust@latest
#   mise use --global go@latest

[tools]
# (empty by default — uncomment what you need)
# python = "3.12"
# node = "lts"

[settings]
auto_install = false
verbose = false
jobs = 4
EOF
        success "Created ~/.config/mise/config.toml"
    fi
}

_install_docker() {
    if command -v docker &>/dev/null && docker --version &>/dev/null; then
        success "Docker already installed: $(docker --version)"
    else
        log "Removing conflicting older Docker packages (if any)..."
        if [[ "$DRY_RUN" != "true" ]]; then
            for pkg in docker.io docker-doc docker-compose docker-compose-v2 \
                       podman-docker containerd runc; do
                sudo apt-get remove -y "$pkg" >>"$LOG_FILE" 2>&1 || true
            done
        fi

        log "Adding Docker official repo..."
        local codename
        codename="$(ubuntu_codename)"
        apt_add_repo docker \
            "https://download.docker.com/linux/ubuntu/gpg" \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"

        log "Installing Docker CE + Compose v2 plugin..."
        apt_install \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin \
            docker-ce-rootless-extras
    fi

    # Add user to docker group (idempotent)
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! id -nG "$USER" | grep -qw docker; then
            sudo usermod -aG docker "$USER"
            warn "Added $USER to docker group — log out + log back in (or run 'newgrp docker') to apply"
        else
            success "$USER already in docker group"
        fi
    fi

    # Daemon config (log rotation, overlay2)
    if [[ "$DRY_RUN" != "true" ]] && [[ ! -f /etc/docker/daemon.json ]]; then
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "storage-driver": "overlay2"
}
EOF
        sudo systemctl restart docker >>"$LOG_FILE" 2>&1 || true
        success "Docker daemon config written + service restarted"
    fi
}

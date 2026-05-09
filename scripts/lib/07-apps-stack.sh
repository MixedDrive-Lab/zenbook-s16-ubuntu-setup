#!/usr/bin/env bash
# ============================================================================
# Section 07 — Apps stack (optional, --with-apps)
#
# A curated set of productivity apps that work well on Linux:
#   * 1Password         password manager (proprietary)
#   * Google Chrome     browser (proprietary)
#   * LocalSend         AirDrop alternative for LAN file transfer (open source)
#   * Typora            markdown WYSIWYG editor (proprietary, paid)
#   * Gum               Charm CLI prompts (open source)
#   * LazyGit           Git TUI (open source)
#   * LazyDocker        Docker TUI (open source)
#   * Ulauncher         App launcher with extensions (open source)
#
# Mix of open source and proprietary — pick & choose by sourcing only the
# functions you want, or pass --skip-app=<name> (TODO future flag).
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_07_apps_stack() {
    log "=== Section 07: Apps stack ==="

    _install_gum
    _install_1password
    _install_chrome
    _install_localsend
    _install_typora
    _install_lazygit
    _install_lazydocker
    _install_ulauncher

    success "Section 07 complete"
}

_install_gum() {
    if command -v gum &>/dev/null; then
        success "Gum already installed"
        return 0
    fi
    log "Installing Gum (Charm CLI prompts)..."
    local version="0.17.0"
    install_deb \
        "https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_amd64.deb" \
        gum
}

_install_1password() {
    if command -v 1password &>/dev/null; then
        success "1Password already installed"
        return 0
    fi
    log "Installing 1Password desktop..."
    install_deb \
        "https://downloads.1password.com/linux/debian/amd64/stable/1password-latest.deb" \
        1password
}

_install_chrome() {
    if command -v google-chrome &>/dev/null; then
        success "Google Chrome already installed"
        return 0
    fi
    log "Installing Google Chrome..."
    install_deb \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
        google-chrome-stable

    if [[ "$DRY_RUN" != "true" ]]; then
        xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null \
            && success "Chrome set as default browser" \
            || warn "Could not set Chrome as default (Wayland portal? — set manually in Settings)"
    fi
}

_install_localsend() {
    if dpkg -l localsend 2>/dev/null | grep -q "^ii"; then
        success "LocalSend already installed"
        return 0
    fi
    log "Installing LocalSend (LAN file transfer)..."
    local version
    version="$(gh_latest_tag localsend/localsend)"
    if [[ -z "$version" ]]; then
        warn "Could not fetch latest LocalSend version, skipping"
        return 1
    fi
    install_deb \
        "https://github.com/localsend/localsend/releases/latest/download/LocalSend-${version}-linux-x86-64.deb" \
        localsend
}

_install_typora() {
    if command -v typora &>/dev/null; then
        success "Typora already installed"
        return 0
    fi
    log "Adding Typora APT repo..."
    if [[ -f /etc/apt/sources.list.d/typora.list ]]; then
        success "Typora repo already configured"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] add Typora apt repo + install typora"
            return 0
        fi
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://downloads.typora.io/typora.gpg \
            | sudo tee /etc/apt/keyrings/typora.gpg >/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/typora.gpg] https://downloads.typora.io/linux ./" \
            | sudo tee /etc/apt/sources.list.d/typora.list >/dev/null
        sudo apt update >>"$LOG_FILE" 2>&1
    fi
    apt_install typora
}

_install_lazygit() {
    if command -v lazygit &>/dev/null; then
        success "LazyGit already installed"
        return 0
    fi
    log "Installing LazyGit..."
    local version
    version="$(gh_latest_tag jesseduffield/lazygit)"
    if [[ -z "$version" ]]; then
        warn "Could not fetch latest LazyGit version, skipping"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] download + install lazygit ${version}"
        return 0
    fi
    local tmp_tar
    tmp_tar=$(mktemp --suffix=.tar.gz)
    if curl -fsSL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${version}_Linux_x86_64.tar.gz" -o "$tmp_tar"; then
        tar -xzf "$tmp_tar" -C /tmp lazygit
        sudo install /tmp/lazygit /usr/local/bin/
        rm -f "$tmp_tar" /tmp/lazygit
        ensure_dir "$HOME/.config/lazygit"
        touch "$HOME/.config/lazygit/config.yml"
        success "LazyGit installed"
    else
        rm -f "$tmp_tar"
        error "LazyGit download failed"
    fi
}

_install_lazydocker() {
    if command -v lazydocker &>/dev/null; then
        success "LazyDocker already installed"
        return 0
    fi
    log "Installing LazyDocker..."
    local version
    version="$(gh_latest_tag jesseduffield/lazydocker)"
    if [[ -z "$version" ]]; then
        warn "Could not fetch latest LazyDocker version, skipping"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] download + install lazydocker ${version}"
        return 0
    fi
    local tmp_tar
    tmp_tar=$(mktemp --suffix=.tar.gz)
    if curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_${version}_Linux_x86_64.tar.gz" -o "$tmp_tar"; then
        tar -xzf "$tmp_tar" -C /tmp lazydocker
        sudo install /tmp/lazydocker /usr/local/bin/
        rm -f "$tmp_tar" /tmp/lazydocker
        success "LazyDocker installed"
    else
        rm -f "$tmp_tar"
        error "LazyDocker download failed"
    fi
}

_install_ulauncher() {
    if command -v ulauncher &>/dev/null; then
        success "Ulauncher already installed"
        return 0
    fi
    log "Installing Ulauncher (PPA)..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] add ppa:agornostal/ulauncher + install ulauncher"
        return 0
    fi
    sudo add-apt-repository -y universe >>"$LOG_FILE" 2>&1
    sudo add-apt-repository -y ppa:agornostal/ulauncher >>"$LOG_FILE" 2>&1
    sudo apt update >>"$LOG_FILE" 2>&1
    sudo apt install -y ulauncher >>"$LOG_FILE" 2>&1 || error "Ulauncher install failed"
    success "Ulauncher installed (configure hotkey via Settings)"
}

#!/usr/bin/env bash
# ============================================================================
# Section 06 — AI stack (optional, --with-ai-stack)
#
# Installs:
#   * Cursor (apt repo at downloads.cursor.com/aptrepo)
#   * Warp Terminal (.deb)
#   * Node.js 22 LTS (NodeSource repo) — needed by Claude Code CLI
#   * Claude Code CLI (npm global)
#
# These are vendor-specific tools; opt in only if you actively use them.
# Free-tier alternatives:
#   * Cursor → VSCodium / VS Code
#   * Warp → kitty / wezterm / alacritty
#   * Claude Code → bring your own LLM CLI
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_06_ai_stack() {
    log "=== Section 06: AI stack (Cursor + Warp + Node.js + Claude Code) ==="

    # libfuse2 is needed for AppImage (Cursor)
    apt_install libfuse2

    _install_cursor
    _install_warp
    _install_nodejs
    _install_claude_code

    success "Section 06 complete"
}

_install_cursor() {
    if command -v cursor &>/dev/null; then
        success "Cursor already installed: $(cursor --version 2>/dev/null | head -1 || echo 'present')"
        return 0
    fi

    # Cursor migrated from AppImage download to an official APT repo.
    # If the repo is already present (Cursor team auto-set it up for some users),
    # skip the key+repo dance and jump straight to apt install.
    if [[ ! -f /etc/apt/sources.list.d/cursor.list ]] \
       && [[ ! -f /etc/apt/sources.list.d/cursor.sources ]]; then
        log "Adding Cursor APT repository..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] would add Cursor apt repo"
        else
            sudo install -m 0755 -d /etc/apt/keyrings
            if ! curl -fsSL https://downloads.cursor.com/aptrepo/public.gpg.key \
                | sudo gpg --dearmor -o /etc/apt/keyrings/cursor.gpg 2>/dev/null; then
                error "Cursor GPG key download failed"
                return 1
            fi
            sudo chmod a+r /etc/apt/keyrings/cursor.gpg
            echo "deb [signed-by=/etc/apt/keyrings/cursor.gpg arch=amd64] https://downloads.cursor.com/aptrepo stable main" \
                | sudo tee /etc/apt/sources.list.d/cursor.list >/dev/null
            sudo apt update >>"$LOG_FILE" 2>&1
        fi
    else
        success "Cursor APT repo already configured"
        # Make sure cache reflects what's there
        if [[ "$DRY_RUN" != "true" ]]; then
            sudo apt update >>"$LOG_FILE" 2>&1
        fi
    fi

    log "Installing Cursor via apt..."
    apt_install cursor

    # Sanity: confirm binary present
    if [[ "$DRY_RUN" != "true" ]] && ! command -v cursor &>/dev/null; then
        warn "Cursor apt install reported success but 'cursor' binary not in PATH."
        warn "Try: which cursor; dpkg -L cursor | grep bin"
    fi
}

_install_warp() {
    if command -v warp-terminal &>/dev/null; then
        success "Warp already installed"
        return 0
    fi

    log "Installing Warp Terminal..."
    install_deb "https://app.warp.dev/download?package=deb" warp-terminal
}

_install_nodejs() {
    if command -v node &>/dev/null; then
        local node_ver
        node_ver="$(node --version 2>/dev/null)"
        success "Node.js already installed: $node_ver"
        return 0
    fi

    log "Installing Node.js 22 LTS via NodeSource..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] curl NodeSource setup_22.x | bash + apt install nodejs"
        return 0
    fi

    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >>"$LOG_FILE" 2>&1
    sudo apt install -y nodejs >>"$LOG_FILE" 2>&1 || {
        error "Node.js install failed"
        return 1
    }
    success "Node.js $(node --version) installed"
}

_install_claude_code() {
    if command -v claude &>/dev/null; then
        success "Claude Code CLI already installed"
        return 0
    fi

    if ! command -v npm &>/dev/null; then
        warn "npm not available — skipping Claude Code (install Node.js first)"
        return 1
    fi

    log "Installing Claude Code CLI globally..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo npm install -g @anthropic-ai/claude-code"
        return 0
    fi

    sudo npm install -g @anthropic-ai/claude-code >>"$LOG_FILE" 2>&1 || {
        error "Claude Code install failed"
        return 1
    }
    success "Claude Code CLI installed"
    log "Run 'claude login' interactively to authenticate."
}

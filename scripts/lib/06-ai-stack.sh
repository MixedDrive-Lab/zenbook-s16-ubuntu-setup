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

    # 2026-05: Cursor's old APT repo at downloads.cursor.com/aptrepo returns
    # HTTP 403 — the channel was removed. Cursor now ships only the .deb via
    # the api2.cursor.sh "golden/latest" channel (used by their auto-updater).
    # We fetch + install that directly.
    local cursor_url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest"

    # Clean up any leftover broken repo files from older versions of this script
    if [[ -f /etc/apt/sources.list.d/cursor.list ]] || \
       [[ -f /etc/apt/keyrings/cursor.gpg ]]; then
        log "Removing stale Cursor APT repo (channel was deprecated)..."
        if [[ "$DRY_RUN" != "true" ]]; then
            sudo rm -f /etc/apt/sources.list.d/cursor.list \
                       /etc/apt/sources.list.d/cursor.sources \
                       /etc/apt/keyrings/cursor.gpg
            sudo apt update >>"$LOG_FILE" 2>&1 || true
        fi
    fi

    log "Installing Cursor (~173 MB .deb from cursor.com)..."
    install_deb "$cursor_url" cursor

    # Sanity: confirm binary present
    if [[ "$DRY_RUN" != "true" ]] && ! command -v cursor &>/dev/null; then
        warn "Cursor install reported success but 'cursor' binary not in PATH."
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

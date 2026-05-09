#!/usr/bin/env bash
# ============================================================================
# Section 12 — mise default languages (--with-mise-defaults)
#
# Optional opt-in: bulk-install 8 popular language toolchains via mise.
# Section 05 (dev toolchain) installs the `mise` binary itself; this section
# adds the actual languages.
#
# Languages installed:
#   - Python    via mise (3.12 default, 3.13, latest) + uv (Astral)
#   - Node.js   via mise (lts)
#   - Go        via mise (latest)
#   - Java      via mise (21 LTS default, latest)
#   - Ruby      via mise (latest) + Rails gem
#   - Erlang + Elixir via mise (latest) + hex
#   - PHP       via apt + Composer (mise's PHP plugin is fragile re: extensions)
#   - Rust      via rustup (canonical Rust toolchain manager, NOT mise)
#
# Caveats:
#   * Erlang OTP build = 15-30 min on Zenbook S16 (compiles from source).
#     Build deps are installed first.
#   * Python: 3 versions installed side-by-side. Default = 3.12 (broad SLAM/CV
#     compatibility). Per-project override via `.mise.toml` for 3.13 or latest.
#   * Java: 2 versions installed side-by-side. Default = 21 LTS. Per-project
#     override via `.mise.toml` for `latest`.
#   * uv (Astral) installed into mise's default Python via `pip install --user`.
#     Replaces python -m venv + pip + pip-tools workflow.
#   * Rust via rustup lives outside mise. mise's Rust plugin is unused.
#   * Section is idempotent: re-run skips already-installed tools.
#
# Reference:
#   https://mise.jdx.dev/lang/
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_12_mise_defaults() {
    log "=== Section 12: mise default languages ==="

    if ! command -v mise &>/dev/null; then
        error "mise not installed — run Section 05 first."
        return 1
    fi

    # mise needs to be activated for the install commands to drop tools in
    # the right place. Source it explicitly for this shell process.
    if [[ "$DRY_RUN" != "true" ]]; then
        eval "$(mise activate bash --shims)" 2>/dev/null || true
    fi

    _mise_install_node
    _mise_install_python
    _mise_install_go
    _mise_install_java
    _mise_install_ruby
    _mise_install_erlang_elixir
    _apt_install_php_composer
    _install_rust_rustup

    success "Section 12 complete"
    log "Open a fresh terminal so mise activation picks up the new tools,"
    log "or run:  eval \"\$(mise activate bash)\" && mise ls"
}

# ----------------------------------------------------------------------------
# mise-managed languages
# ----------------------------------------------------------------------------

_mise_install_node() {
    log "Installing Node.js (lts) via mise..."
    if mise ls 2>/dev/null | grep -qE '^node\s+lts'; then
        success "node@lts already pinned in mise"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] mise use --global node@lts"
        return 0
    fi
    mise use --global node@lts >>"$LOG_FILE" 2>&1 || warn "mise use node@lts had errors"
    success "Node.js (lts) installed via mise"
}

_mise_install_python() {
    log "Installing Python (3.12, 3.13, latest) via mise..."
    log "  Default = 3.12 (broad SLAM/CV ecosystem support)."
    log "  3.13 + latest available for per-project switching via .mise.toml."

    # mise accepts multiple versions in one `use` call. First listed = default
    # for `python` command; specific versions accessible as python3.13, etc.
    if mise ls 2>/dev/null | grep -qE '^python\s+3\.12'; then
        success "python@3.12 already pinned in mise (skipping multi-install)"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] mise use --global python@3.12 python@3.13 python@latest"
        else
            mise use --global python@3.12 python@3.13 python@latest \
                >>"$LOG_FILE" 2>&1 || warn "mise use python@multi had errors"
            success "Python (3.12, 3.13, latest) installed via mise"
        fi
    fi

    # Install uv (Astral's fast Python package manager — replaces pip + venv +
    # pip-tools) into mise's default Python (3.12). Available globally via
    # mise's PATH ordering.
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] mise x python -- pip install --user uv"
        return 0
    fi

    if mise x python -- python -m uv --version &>/dev/null; then
        success "uv already installed in mise's Python"
    else
        log "Installing uv (Astral) into mise's default Python..."
        if mise x python -- python -m pip install --user uv >>"$LOG_FILE" 2>&1; then
            success "uv installed (run 'uv --help' to get started)"
        else
            warn "uv install failed — try manually: mise x python -- pip install --user uv"
        fi
    fi
}

_mise_install_go() {
    log "Installing Go (latest) via mise..."
    if mise ls 2>/dev/null | grep -qE '^go\s+latest'; then
        success "go@latest already pinned in mise"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] mise use --global go@latest"
        return 0
    fi
    mise use --global go@latest >>"$LOG_FILE" 2>&1 || warn "mise use go@latest had errors"
    success "Go (latest) installed via mise"
}

_mise_install_java() {
    log "Installing Java (21 LTS, latest) via mise..."
    log "  Default = 21 (current LTS, broad ecosystem support)."
    log "  latest available for bleeding-edge experiments via .mise.toml override."

    if mise ls 2>/dev/null | grep -qE '^java\s+21'; then
        success "java@21 already pinned in mise (skipping multi-install)"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] mise use --global java@21 java@latest"
        return 0
    fi
    mise use --global java@21 java@latest >>"$LOG_FILE" 2>&1 \
        || warn "mise use java@multi had errors"
    success "Java (21 LTS, latest) installed via mise"
}

_mise_install_ruby() {
    log "Installing Ruby (latest) via mise + Rails..."
    if mise ls 2>/dev/null | grep -qE '^ruby\s+latest'; then
        success "ruby@latest already pinned in mise"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] mise use --global ruby@latest"
        else
            mise use --global ruby@latest >>"$LOG_FILE" 2>&1 || {
                warn "mise use ruby@latest had errors"
                return 1
            }
            success "Ruby (latest) installed via mise"
        fi
    fi

    # Idiomatic version file detection (.ruby-version) — only enable once.
    if [[ "$DRY_RUN" != "true" ]]; then
        if mise settings get idiomatic_version_file_enable_tools 2>/dev/null \
           | grep -qw ruby; then
            success "mise idiomatic_version_file_enable_tools already includes ruby"
        else
            mise settings add idiomatic_version_file_enable_tools ruby \
                >>"$LOG_FILE" 2>&1 || warn "mise settings add ruby had errors"
            success "Enabled .ruby-version detection in mise"
        fi
    fi

    # Rails — heavy dep tree but explicit user choice.
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] gem install rails --no-document"
        return 0
    fi
    if mise x ruby -- gem list -i rails &>/dev/null; then
        success "Rails gem already installed"
    else
        log "Installing Rails gem (this can take 2-5 min)..."
        mise x ruby -- gem install rails --no-document >>"$LOG_FILE" 2>&1 \
            || warn "Rails gem install had errors (Ruby still usable)"
        success "Rails gem installed"
    fi
}

_mise_install_erlang_elixir() {
    log "Installing Erlang + Elixir via mise..."
    warn "Erlang OTP builds from source — this can take 15-30 min on a Zenbook S16."

    # Build deps for Erlang OTP (asdf-erlang docs reference list).
    log "Installing Erlang build dependencies (apt)..."
    apt_install \
        autoconf m4 libncurses-dev libwxgtk3.2-dev libwxgtk-webview3.2-dev \
        libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev \
        unixodbc-dev xsltproc fop libxml2-utils libncurses5-dev \
        || warn "Some Erlang build deps had errors — Erlang build may fail"

    # Erlang first
    if mise ls 2>/dev/null | grep -qE '^erlang\s+latest'; then
        success "erlang@latest already pinned in mise"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] mise use --global erlang@latest (15-30 min build)"
        else
            log "Building Erlang OTP from source via mise (long-running)..."
            mise use --global erlang@latest >>"$LOG_FILE" 2>&1 || {
                error "Erlang build failed — check $LOG_FILE for details"
                warn "Skipping Elixir (depends on Erlang)"
                return 1
            }
            success "Erlang (latest) installed via mise"
        fi
    fi

    # Elixir (needs Erlang first)
    if mise ls 2>/dev/null | grep -qE '^elixir\s+latest'; then
        success "elixir@latest already pinned in mise"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] mise use --global elixir@latest"
        else
            mise use --global elixir@latest >>"$LOG_FILE" 2>&1 || {
                warn "mise use elixir@latest had errors"
                return 1
            }
            success "Elixir (latest) installed via mise"
        fi
    fi

    # Hex package manager (Elixir)
    if [[ "$DRY_RUN" != "true" ]] && command -v mise &>/dev/null; then
        if mise x elixir -- mix archive | grep -q hex 2>/dev/null; then
            success "Hex (Elixir package manager) already installed"
        else
            mise x elixir -- mix local.hex --force >>"$LOG_FILE" 2>&1 \
                || warn "mix local.hex had errors"
            success "Hex (Elixir package manager) installed"
        fi
    fi
}

# ----------------------------------------------------------------------------
# apt-managed: PHP + Composer
# ----------------------------------------------------------------------------

_apt_install_php_composer() {
    log "Installing PHP via apt (mise's PHP plugin requires re-builds for extensions)..."

    # PHP + commonly-needed extensions
    apt_install \
        php \
        php-curl php-apcu php-intl php-mbstring php-opcache \
        php-pgsql php-mysql php-sqlite3 php-redis \
        php-xml php-zip

    # Composer — install to /usr/local/bin via official installer
    if command -v composer &>/dev/null; then
        success "Composer already installed: $(composer --version 2>/dev/null | head -1)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] download + install Composer to /usr/local/bin/composer"
        return 0
    fi

    log "Installing Composer..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    pushd "$tmp_dir" >/dev/null || return 1

    if php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
       && php composer-setup.php --quiet \
       && sudo mv composer.phar /usr/local/bin/composer; then
        success "Composer installed at /usr/local/bin/composer"
    else
        error "Composer install failed"
    fi

    popd >/dev/null || true
    rm -rf "$tmp_dir"
}

# ----------------------------------------------------------------------------
# rustup-managed: Rust (canonical, outside mise)
# ----------------------------------------------------------------------------

_install_rust_rustup() {
    if command -v rustup &>/dev/null && command -v cargo &>/dev/null; then
        success "Rust already installed: $(rustc --version 2>/dev/null | head -1)"
        return 0
    fi

    log "Installing Rust via rustup (canonical Rust toolchain manager, NOT mise)..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] curl rustup-init | sh -s -- -y"
        return 0
    fi

    # Note: rustup-init.sh -y installs to ~/.cargo/, modifies ~/.bashrc / ~/.profile
    # to add ~/.cargo/bin to PATH. Idempotent — re-running -y just updates.
    if bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)" -- -y \
       >>"$LOG_FILE" 2>&1; then
        success "Rust installed via rustup at ~/.cargo/"
        log "Open a fresh terminal (or 'source ~/.cargo/env') for cargo/rustc to be in PATH."
    else
        error "rustup install failed"
        return 1
    fi
}

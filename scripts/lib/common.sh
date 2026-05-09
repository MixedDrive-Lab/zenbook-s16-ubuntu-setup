#!/usr/bin/env bash
# ============================================================================
# zenbook-s16-ubuntu-setup — shared utilities
# Sourced by scripts/setup.sh and individual section scripts.
# Do NOT execute directly.
# ============================================================================

# Strict-ish mode (set -e disabled deliberately so per-step errors don't abort
# the whole run; each section handles its own failures via run_cmd).
set -u
set -o pipefail

# Colors (skip if NO_COLOR is set or stdout is not a tty)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_NC='\033[0m'
else
    COLOR_RED='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_NC=''
fi

# Defaults — overridable from setup.sh
: "${DRY_RUN:=false}"
: "${LOG_FILE:=$HOME/.cache/zenbook-s16-setup/setup-$(date +%Y%m%d-%H%M%S).log}"

# Make sure log dir exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
    local msg="$1"
    echo -e "${COLOR_BLUE}[$(date +%H:%M:%S)]${COLOR_NC} $msg" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1" | tee -a "$LOG_FILE" >&2
}

# Run a command with logging. Returns the command's exit code.
# Usage: run_cmd "description" command args...
run_cmd() {
    local description="$1"
    shift
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] $description: $*"
        return 0
    fi
    log "$description"
    if "$@" >>"$LOG_FILE" 2>&1; then
        return 0
    else
        local rc=$?
        error "$description failed (exit $rc) — see $LOG_FILE"
        return "$rc"
    fi
}

# Install APT packages idempotently. Skips packages already installed.
# Usage: apt_install pkg1 pkg2 ...
apt_install() {
    local pkgs=("$@")
    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        success "All ${#pkgs[@]} package(s) already installed: ${pkgs[*]}"
        return 0
    fi
    log "Installing ${#missing[@]} missing package(s): ${missing[*]}"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo apt install -y ${missing[*]}"
        return 0
    fi
    sudo apt install -y "${missing[@]}" >>"$LOG_FILE" 2>&1 || {
        error "apt install failed for: ${missing[*]}"
        return 1
    }
    success "Installed: ${missing[*]}"
}

# Add an APT repository idempotently (key + sources.list.d entry).
# Usage: apt_add_repo NAME KEY_URL "REPO_LINE"
# Example: apt_add_repo docker https://download.docker.com/linux/ubuntu/gpg \
#          "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable"
apt_add_repo() {
    local name="$1"
    local key_url="$2"
    local repo_line="$3"
    local list_file="/etc/apt/sources.list.d/${name}.list"
    local key_file="/etc/apt/keyrings/${name}.asc"

    if [[ -f "$list_file" ]] && [[ -f "$key_file" ]]; then
        success "APT repo '$name' already configured"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would add APT repo $name (key: $key_url)"
        return 0
    fi

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "$key_url" -o "$key_file" || {
        error "Failed to download key for $name from $key_url"
        return 1
    }
    sudo chmod a+r "$key_file"
    echo "$repo_line" | sudo tee "$list_file" >/dev/null
    sudo apt update >>"$LOG_FILE" 2>&1
    success "APT repo '$name' added"
}

# Install a flatpak app idempotently from flathub.
# Usage: flatpak_install com.example.App "Display Name"
flatpak_install() {
    local app_id="$1"
    local label="${2:-$app_id}"
    if ! command -v flatpak &>/dev/null; then
        warn "flatpak not installed, skipping $label"
        return 1
    fi
    if flatpak list --app 2>/dev/null | awk '{print $2}' | grep -qx "$app_id"; then
        success "$label already installed"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] flatpak install flathub $app_id"
        return 0
    fi
    log "Installing flatpak app: $label ($app_id)"
    sudo flatpak install -y --noninteractive flathub "$app_id" >>"$LOG_FILE" 2>&1 || {
        error "Flatpak install failed for $app_id"
        return 1
    }
    success "$label installed"
}

# Ensure a directory exists with correct ownership.
ensure_dir() {
    local dir="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] mkdir -p $dir"
        return 0
    fi
    mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir"
    if [[ ! -w "$dir" ]]; then
        sudo chown "$USER:$USER" "$dir" 2>/dev/null || true
    fi
}

# Resolve the Ubuntu codename (e.g. "noble" for 24.04). Cached.
ubuntu_codename() {
    if [[ -z "${_UBUNTU_CODENAME:-}" ]]; then
        _UBUNTU_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    fi
    echo "$_UBUNTU_CODENAME"
}

# Download a deb from a URL, install it, clean up.
# Usage: install_deb URL [PACKAGE_NAME_TO_CHECK]
install_deb() {
    local url="$1"
    local check_pkg="${2:-}"

    if [[ -n "$check_pkg" ]] && dpkg -l "$check_pkg" 2>/dev/null | grep -q "^ii"; then
        success "$check_pkg already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] download + install deb: $url"
        return 0
    fi

    local tmp_deb
    tmp_deb=$(mktemp --suffix=.deb)
    log "Downloading $url"
    if ! curl -fsSL "$url" -o "$tmp_deb"; then
        error "Download failed: $url"
        rm -f "$tmp_deb"
        return 1
    fi
    sudo apt install -y "$tmp_deb" >>"$LOG_FILE" 2>&1 || {
        error "Install failed for deb from $url"
        rm -f "$tmp_deb"
        return 1
    }
    rm -f "$tmp_deb"
    success "Installed deb from $url"
}

# Get the latest GitHub release tag for owner/repo (semver, no leading 'v').
# Usage: gh_latest_tag owner/repo
gh_latest_tag() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -Po '"tag_name":\s*"v?\K[^"]*' \
        | head -1
}

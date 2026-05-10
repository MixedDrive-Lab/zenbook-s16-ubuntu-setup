#!/usr/bin/env bash
# ============================================================================
# Section 01 — Pre-flight checks
# Verifies that the system meets the minimum prerequisites before we touch it.
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_01_preflight() {
    log "=== Section 01: Pre-flight checks ==="

    local fatal=0

    # Ubuntu version
    if [[ ! -f /etc/os-release ]]; then
        error "/etc/os-release missing — not an Ubuntu system?"
        return 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        error "This script targets Ubuntu. Detected: ${ID:-unknown}"
        fatal=1
    fi
    case "${VERSION_ID:-}" in
        "24.04") success "Ubuntu 24.04 LTS detected (target)" ;;
        "24.10"|"25.04"|"25.10")
            warn "Ubuntu ${VERSION_ID} detected — script targets 24.04 LTS but should mostly work"
            ;;
        *)
            warn "Ubuntu ${VERSION_ID:-unknown} — untested. Continue at your own risk."
            ;;
    esac

    # Architecture
    local arch
    arch="$(dpkg --print-architecture)"
    if [[ "$arch" != "amd64" ]]; then
        error "This script targets amd64. Detected: $arch"
        fatal=1
    else
        success "Architecture: amd64"
    fi

    # Sudo
    if ! sudo -n true 2>/dev/null; then
        log "Sudo password required — prompting now to cache for the rest of the run"
        if ! sudo -v; then
            error "Sudo authentication failed"
            return 1
        fi
    fi
    success "Sudo available"

    # Internet — skip in dry-run (curl may not exist yet on a fresh system,
    # and bootstrap_minimal_deps already installed it for real if missing).
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Internet check skipped (dry-run)"
    elif command -v curl >/dev/null 2>&1 \
        && curl -fsSL --max-time 5 https://archive.ubuntu.com/ -o /dev/null 2>&1; then
        success "Internet reachable"
    else
        error "Cannot reach archive.ubuntu.com — check your network"
        fatal=1
    fi

    # Disk space (need ~15 GB free for full install)
    local free_gb
    free_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    if [[ "$free_gb" -lt 15 ]]; then
        warn "Free space on /: ${free_gb}GB (recommended ≥15 GB)"
    else
        success "Free space on /: ${free_gb}GB"
    fi

    # Display server (informational)
    case "${XDG_SESSION_TYPE:-unknown}" in
        wayland) success "Wayland session active (recommended)" ;;
        x11) warn "X11 session — Wayland recommended for Zenbook S16 (HDR / hi-DPI)" ;;
        *) warn "Display server unknown (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset})" ;;
    esac

    # Hardware sanity (laptop model)
    local product
    product=$(sudo cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "unknown")
    if echo "$product" | grep -qi "UM5606\|Zenbook S 16"; then
        success "Hardware: $product (target)"
    else
        warn "Hardware: $product — script optimized for ASUS Zenbook S16 (UM5606)"
        warn "  Most steps still apply for AMD Ryzen AI / generic Ubuntu setup."
    fi

    if [[ "$fatal" -ne 0 ]]; then
        error "Pre-flight failed. Aborting."
        return 1
    fi

    success "Section 01 complete"
}

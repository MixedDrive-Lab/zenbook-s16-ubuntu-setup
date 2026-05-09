#!/usr/bin/env bash
# ============================================================================
# Section 09 — Gaming stack (optional, --with-gaming)
#
# Installs:
#   * Steam (apt, multiverse repo + i386 architecture)
#   * ProtonUp-Qt (Flatpak) — manage GE-Proton versions
#
# Note: Steam Linux requires:
#   - `multiverse` repo enabled (steam-installer is in multiverse)
#   - i386 architecture enabled (steam-libs-i386 dependency)
# Both are configured automatically before `apt install`.
#
# After install, manually:
#   1. Open Steam → log in
#   2. Settings → Compatibility → Enable Steam Play for all titles
#   3. ProtonUp-Qt → Add version → install GE-Proton (latest)
#   4. Per-game: Properties → Compatibility → Force Proton/GE-Proton
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_09_gaming() {
    log "=== Section 09: Gaming stack (Steam + ProtonUp-Qt) ==="

    # Steam needs:
    #   1. multiverse repo enabled (for steam-installer)
    #   2. i386 (32-bit) architecture enabled (for steam-libs-i386 dep)
    # Both must be in place BEFORE apt install steam-installer.

    if [[ "$DRY_RUN" != "true" ]]; then
        # Enable multiverse
        sudo add-apt-repository -y multiverse >>"$LOG_FILE" 2>&1 || true

        # Enable i386 architecture (idempotent)
        if ! dpkg --print-foreign-architectures | grep -qx i386; then
            log "Adding i386 architecture for Steam 32-bit libraries..."
            sudo dpkg --add-architecture i386 >>"$LOG_FILE" 2>&1
        else
            success "i386 architecture already enabled"
        fi

        # Refresh package lists with multiverse + i386 in place
        sudo apt update >>"$LOG_FILE" 2>&1
    fi

    apt_install steam-installer

    if command -v flatpak &>/dev/null; then
        flatpak_install "net.davidotek.pupgui2" "ProtonUp-Qt"
    else
        warn "flatpak not available — skipping ProtonUp-Qt (install via section 03 first)"
    fi

    success "Section 09 complete"
    log "Next steps (manual):"
    log "  1. Launch Steam, sign in"
    log "  2. Settings → Compatibility → Enable Steam Play for all titles"
    log "  3. Open ProtonUp-Qt → install GE-Proton latest"
}

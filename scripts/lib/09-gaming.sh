#!/usr/bin/env bash
# ============================================================================
# Section 09 — Gaming stack (optional, --with-gaming)
#
# Installs:
#   * Steam (apt, multiverse repo)
#   * ProtonUp-Qt (Flatpak) — manage GE-Proton versions
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

    # Enable multiverse for Steam
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo add-apt-repository -y multiverse >>"$LOG_FILE" 2>&1 || true
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

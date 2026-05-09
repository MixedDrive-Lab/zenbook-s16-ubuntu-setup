#!/usr/bin/env bash
# ============================================================================
# Section 08 — Flatpak apps (optional, --with-flatpak)
#
# Why Flatpak instead of apt for these:
#   * Codec freshness for media tools (Audacity, GIMP, VLC, HandBrake, Kdenlive)
#   * Sandboxing for closed-source apps (Spotify, Discord, Zoom)
#   * No conflict with system ffmpeg / system libraries
#   * Faster upstream release cadence than the Ubuntu archive
#
# Productivity:
#   * OnlyOffice — Microsoft Office compatibility (better than LibreOffice for .xlsx)
#   * Obsidian   — Markdown-based knowledge management
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_08_flatpak_apps() {
    log "=== Section 08: Flatpak apps ==="

    if ! command -v flatpak &>/dev/null; then
        error "flatpak not installed — run Section 03 first"
        return 1
    fi

    # Productivity
    flatpak_install "org.onlyoffice.desktopeditors" "OnlyOffice Desktop"
    flatpak_install "md.obsidian.Obsidian"           "Obsidian"

    # Media
    flatpak_install "org.audacityteam.Audacity"      "Audacity"
    flatpak_install "org.gimp.GIMP"                  "GIMP"
    flatpak_install "com.github.PintaProject.Pinta"  "Pinta"
    flatpak_install "org.videolan.VLC"               "VLC"
    flatpak_install "fr.handbrake.ghb"               "HandBrake"
    flatpak_install "org.kde.kdenlive"               "Kdenlive"

    # Comms
    flatpak_install "com.spotify.Client"             "Spotify"
    flatpak_install "com.discordapp.Discord"         "Discord"
    flatpak_install "us.zoom.Zoom"                   "Zoom"

    success "Section 08 complete"
}

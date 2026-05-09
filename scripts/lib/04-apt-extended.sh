#!/usr/bin/env bash
# ============================================================================
# Section 04 — Extended APT (runtime libs + Vulkan/Mesa + system monitor)
#
# These are the libraries that pay off the moment you start building real
# software on the Zenbook S16:
#
#   * Runtime libs: needed to build Ruby, Python C-extensions, native gems,
#     image processing, database client libs, etc.
#   * Vulkan/Mesa: required for Steam/Proton, GPU compute, hardware video
#     acceleration in Kdenlive/HandBrake.
#   * System monitor: thermald + lm-sensors are non-optional on a thin&light
#     laptop; stress-ng is handy for thermal validation.
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

run_section_04_apt_extended() {
    log "=== Section 04: Extended APT (libs + Vulkan/Mesa + monitor) ==="

    log "Installing extended runtime libraries..."
    apt_install \
        libssl-dev libreadline-dev zlib1g-dev libyaml-dev libncurses5-dev \
        libffi-dev libgdbm-dev libjemalloc2 \
        libvips imagemagick libmagickwand-dev \
        mupdf mupdf-tools \
        redis-tools sqlite3 libsqlite3-0 \
        libmysqlclient-dev libpq-dev \
        postgresql-client postgresql-client-common

    log "Installing SLAM / robotics dev libraries (optional but small)..."
    apt_install \
        libeigen3-dev libopencv-dev \
        libceres-dev libgtest-dev

    log "Installing Vulkan + Mesa GPU stack..."
    apt_install \
        vulkan-tools clinfo mesa-utils \
        mesa-vulkan-drivers libvulkan1 vulkan-validationlayers \
        libegl1-mesa-dev libgles2-mesa-dev libgl1-mesa-dri libglx-mesa0 \
        mesa-va-drivers mesa-vdpau-drivers \
        libdrm-amdgpu1 libva2 libva-drm2 libva-x11-2 vainfo \
        intel-media-va-driver-non-free

    log "Installing kernel tools + system monitor..."
    apt_install \
        linux-tools-generic linux-tools-common \
        linux-headers-generic-hwe-24.04 \
        thermald lm-sensors stress-ng

    # Initialise lm-sensors (non-interactive)
    if [[ "$DRY_RUN" != "true" ]] && command -v sensors-detect &>/dev/null; then
        if [[ ! -f /etc/sensors3.conf.scanned ]]; then
            log "Running sensors-detect (auto, no kernel module probing)..."
            sudo sensors-detect --auto >>"$LOG_FILE" 2>&1 || warn "sensors-detect returned non-zero"
            sudo touch /etc/sensors3.conf.scanned
        fi
    fi

    # FastFetch via PPA
    if command -v fastfetch &>/dev/null; then
        success "fastfetch already installed"
    else
        log "Adding fastfetch PPA + installing..."
        if [[ "$DRY_RUN" != "true" ]]; then
            sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch >>"$LOG_FILE" 2>&1
            sudo apt update >>"$LOG_FILE" 2>&1
            sudo apt install -y fastfetch >>"$LOG_FILE" 2>&1 || error "fastfetch install failed"
            success "fastfetch installed"
        else
            log "[DRY-RUN] would add ppa:zhangsongcui3371/fastfetch + apt install fastfetch"
        fi
    fi

    # Quick Vulkan sanity check (informational, non-fatal)
    if [[ "$DRY_RUN" != "true" ]] && command -v vulkaninfo &>/dev/null; then
        if vulkaninfo --summary 2>/dev/null | grep -qi "Radeon\|amdgpu"; then
            success "Vulkan GPU detected (AMD)"
        else
            warn "vulkaninfo did not report an AMD GPU — verify with: vulkaninfo --summary"
        fi
    fi

    success "Section 04 complete"
}

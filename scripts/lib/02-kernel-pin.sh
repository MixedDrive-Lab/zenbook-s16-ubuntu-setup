#!/usr/bin/env bash
# ============================================================================
# Section 02 — Kernel pinning for amdxdna NPU compatibility
#
# Background: kernel >= 6.17.0-22 introduced a regression that breaks the
# amdxdna driver on AMD Ryzen AI 9 HX 370 (Strix Point), surfacing as:
#   amdxdna_drm_open: SVA bind device failed, ret -95
# Caused by commit "iommu: disable SVA when CONFIG_X86 is set".
# Last known good: 6.17.0-20.
#
# This script:
#   1. Detects current running kernel
#   2. Installs 6.17.0-20 if missing (from apt or noted as fallback)
#   3. Holds the kernel meta-packages so apt-get upgrade won't replace it
#
# Override:
#   ZENBOOK_SKIP_KERNEL_PIN=1 ./setup.sh   # skip this section entirely
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly TARGET_KERNEL="6.17.0-20"

run_section_02_kernel_pin() {
    log "=== Section 02: Kernel pinning (amdxdna NPU fix) ==="

    if [[ "${ZENBOOK_SKIP_KERNEL_PIN:-0}" == "1" ]]; then
        warn "ZENBOOK_SKIP_KERNEL_PIN=1 — skipping kernel pin"
        return 0
    fi

    local current_kernel
    current_kernel="$(uname -r)"
    log "Current kernel: $current_kernel"

    # Already on a 6.17.0-20-generic? Just ensure hold and return.
    if [[ "$current_kernel" == "${TARGET_KERNEL}-generic" ]]; then
        success "Already running target kernel ${TARGET_KERNEL}-generic"
        _hold_kernel_packages
        return 0
    fi

    # Already installed on disk?
    if dpkg -l "linux-image-${TARGET_KERNEL}-generic" 2>/dev/null | grep -q "^ii"; then
        success "Target kernel ${TARGET_KERNEL} already installed (not booted)"
        _set_default_boot
        _hold_kernel_packages
        warn "Reboot required to switch to ${TARGET_KERNEL}-generic"
        return 0
    fi

    # Try to install from apt
    log "Installing linux-image-${TARGET_KERNEL}-generic + headers + modules..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo apt install -y linux-image-${TARGET_KERNEL}-generic linux-headers-${TARGET_KERNEL}-generic linux-modules-${TARGET_KERNEL}-generic linux-modules-extra-${TARGET_KERNEL}-generic"
    else
        sudo apt update >>"$LOG_FILE" 2>&1
        if sudo apt install -y \
            "linux-image-${TARGET_KERNEL}-generic" \
            "linux-headers-${TARGET_KERNEL}-generic" \
            "linux-modules-${TARGET_KERNEL}-generic" \
            "linux-modules-extra-${TARGET_KERNEL}-generic" >>"$LOG_FILE" 2>&1; then
            success "Kernel ${TARGET_KERNEL} installed from apt"
        else
            error "Failed to install kernel ${TARGET_KERNEL} from apt."
            warn "It may have been purged from the active Ubuntu archive."
            warn "Manual fallback options:"
            warn "  1. Mainline PPA: https://kernel.ubuntu.com/~kernel-ppa/mainline/"
            warn "  2. Launchpad archive: https://launchpad.net/ubuntu/+source/linux/+publishinghistory"
            warn "  3. Download .deb files manually and run: sudo dpkg -i linux-{image,headers,modules}-${TARGET_KERNEL}-generic_*.deb"
            return 1
        fi
    fi

    _set_default_boot
    _hold_kernel_packages

    warn "Reboot REQUIRED to switch to kernel ${TARGET_KERNEL}-generic"
    warn "After reboot, verify with: uname -r"
    warn "Then re-run setup.sh to continue with the rest of the install."

    success "Section 02 complete (reboot required)"
}

_hold_kernel_packages() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] apt-mark hold linux-image-generic linux-headers-generic linux-generic"
        return 0
    fi
    log "Holding kernel meta-packages to prevent auto-upgrade past ${TARGET_KERNEL}..."
    sudo apt-mark hold \
        linux-image-generic \
        linux-headers-generic \
        linux-generic >>"$LOG_FILE" 2>&1 || true
    success "Kernel meta-packages held"
    log "To unhold later (when upstream fixes the bug): sudo apt-mark unhold linux-image-generic linux-headers-generic linux-generic"
}

_set_default_boot() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] update-grub"
        return 0
    fi
    log "Updating GRUB so the held kernel is bootable..."
    sudo update-grub >>"$LOG_FILE" 2>&1 || warn "update-grub returned non-zero"
}

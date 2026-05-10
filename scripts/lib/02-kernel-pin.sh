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
readonly GRUB_FAIL_MARKER="$HOME/.cache/zenbook-s16-setup/sec02-grub-fix-needed"

run_section_02_kernel_pin() {
    log "=== Section 02: Kernel pinning (amdxdna NPU fix) ==="

    if [[ "${ZENBOOK_SKIP_KERNEL_PIN:-0}" == "1" ]]; then
        warn "ZENBOOK_SKIP_KERNEL_PIN=1 — skipping kernel pin"
        return 0
    fi

    # Clean any stale GRUB-fail marker from a previous run (we'll re-flag if needed)
    rm -f "$GRUB_FAIL_MARKER" 2>/dev/null || true

    local current_kernel grub_rc=0
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
        _set_default_boot || grub_rc=$?
        _hold_kernel_packages
        if [[ "$grub_rc" -ne 0 ]]; then
            ensure_dir "$(dirname "$GRUB_FAIL_MARKER")"
            date -Iseconds > "$GRUB_FAIL_MARKER"
            warn "GRUB default could NOT be set automatically — see banner for manual fix"
            return 1
        fi
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

    _set_default_boot || grub_rc=$?
    _hold_kernel_packages

    if [[ "$grub_rc" -ne 0 ]]; then
        ensure_dir "$(dirname "$GRUB_FAIL_MARKER")"
        date -Iseconds > "$GRUB_FAIL_MARKER"
        warn "GRUB default could NOT be set automatically — see banner for manual fix"
        return 1
    fi

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
        log "[DRY-RUN] update-grub + set GRUB_DEFAULT to ${TARGET_KERNEL}-generic"
        return 0
    fi

    if [[ ! -f /etc/default/grub ]]; then
        warn "/etc/default/grub missing — skipping GRUB default config"
        return 0
    fi

    # Step 1: regenerate grub.cfg first so we can parse it.
    log "Updating GRUB so the held kernel is bootable..."
    sudo update-grub >>"$LOG_FILE" 2>&1 || warn "update-grub returned non-zero"

    # Step 2: Compute the right GRUB_DEFAULT value for ${TARGET_KERNEL}-generic.
    #
    # Strategy (most-readable + robust → fallback):
    #   A. Title-based: "<submenu_title>><entry_title>" — e.g.
    #        "Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-20-generic"
    #      GRUB supports this format natively. Survives function-defs noise at
    #      the top of grub.cfg (which broke older menuentry-id parsing).
    #   B. menuentry-id (e.g. "gnulinux-advanced-UUID>gnulinux-6.17.0-20-...").
    #   C. Position pair "1>N".
    local target_default=""
    local target_kernel_full="${TARGET_KERNEL}-generic"

    # awk -F"'" splits on single-quotes; on a typical Ubuntu line like:
    #   menuentry 'Ubuntu, with Linux 6.17.0-20-generic' --class ... $menuentry_id_option 'gnulinux-...-advanced-UUID' {
    # field 2 is the visible label, field 4 is the menuentry id.

    # --- Strategy A: title-based ---
    local sub_title menu_title
    sub_title=$(awk -F"'" '/^submenu / { print $2; exit }' /boot/grub/grub.cfg 2>/dev/null)
    menu_title=$(awk -F"'" -v k="$target_kernel_full" '
        /^[[:space:]]*menuentry / && index($0, k) && !/recovery mode/ {
            print $2
            exit
        }' /boot/grub/grub.cfg 2>/dev/null)

    if [[ -n "$sub_title" ]] && [[ -n "$menu_title" ]]; then
        target_default="${sub_title}>${menu_title}"
        log "Resolved GRUB title path: $target_default"
    elif [[ -n "$menu_title" ]]; then
        target_default="$menu_title"
        log "Resolved GRUB title (no submenu): $target_default"
    fi

    # --- Strategy B: menuentry id ---
    if [[ -z "$target_default" ]]; then
        warn "Title-based GRUB_DEFAULT failed — trying menuentry-id fallback"
        local sub_id menu_id
        sub_id=$(awk -F"'" '/^submenu / { print $4; exit }' /boot/grub/grub.cfg 2>/dev/null)
        menu_id=$(awk -F"'" -v k="$target_kernel_full" '
            /^[[:space:]]*menuentry / && index($0, k) && !/recovery mode/ {
                print $4
                exit
            }' /boot/grub/grub.cfg 2>/dev/null)
        if [[ -n "$sub_id" ]] && [[ -n "$menu_id" ]]; then
            target_default="${sub_id}>${menu_id}"
            log "Resolved menuentry id: $target_default"
        elif [[ -n "$menu_id" ]]; then
            target_default="$menu_id"
            log "Resolved menuentry id (no submenu): $target_default"
        fi
    fi

    # --- Strategy C: position fallback "1>N" ---
    if [[ -z "$target_default" ]]; then
        warn "menuentry-id GRUB_DEFAULT failed — trying position-based fallback"
        local pos
        pos=$(awk -F"'" -v k="$target_kernel_full" '
            BEGIN { in_sub = 0; idx = -1 }
            /^submenu /         { in_sub = 1; idx = -1; next }
            /^}/                { if (in_sub) in_sub = 0; next }
            in_sub && /menuentry / {
                idx++
                if (index($0, k) && !/recovery mode/) {
                    print idx
                    exit
                }
            }' /boot/grub/grub.cfg 2>/dev/null)
        if [[ -n "$pos" ]]; then
            target_default="1>${pos}"
            log "Position-based fallback: $target_default"
        fi
    fi

    if [[ -z "$target_default" ]]; then
        error "Could not locate ${target_kernel_full} menuentry in /boot/grub/grub.cfg"
        error "Inspect manually: sudo awk -F\"'\" '/menuentry|submenu/ && !/recovery/ {print NR\": \"\$2}' /boot/grub/grub.cfg"
        error "Then set /etc/default/grub: GRUB_DEFAULT=\"<submenu_title>><entry_title>\" and run sudo update-grub"
        return 1
    fi

    # Step 3: Set GRUB_DEFAULT in /etc/default/grub idempotently.
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${target_default}\"|" /etc/default/grub
    else
        echo "GRUB_DEFAULT=\"${target_default}\"" | sudo tee -a /etc/default/grub >/dev/null
    fi

    # GRUB_SAVEDEFAULT only meaningful with GRUB_DEFAULT=saved; we use a fixed
    # default now, so unset it (commented) to avoid confusion.
    sudo sed -i 's/^GRUB_SAVEDEFAULT=true/#GRUB_SAVEDEFAULT=true/' /etc/default/grub

    success "/etc/default/grub: GRUB_DEFAULT=\"${target_default}\""

    # Step 4: Re-run update-grub so the new GRUB_DEFAULT takes effect.
    log "Regenerating grub.cfg with the new default..."
    sudo update-grub >>"$LOG_FILE" 2>&1 || warn "second update-grub returned non-zero"

    # Step 5: Verification — read back GRUB_DEFAULT and confirm it mentions our kernel.
    local actual
    actual=$(grep '^GRUB_DEFAULT=' /etc/default/grub | head -1)
    log "Final config: $actual"
    if echo "$actual" | grep -q "$TARGET_KERNEL"; then
        success "Verified: GRUB_DEFAULT now references ${target_kernel_full}"
        return 0
    else
        error "GRUB_DEFAULT was set but verification failed"
        error "  Expected to contain: $TARGET_KERNEL"
        error "  Got: $actual"
        return 1
    fi
}

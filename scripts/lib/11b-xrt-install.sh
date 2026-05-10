#!/usr/bin/env bash
# ============================================================================
# Section 11b — XRT install (post-reboot)
#
# Phase 2 of XRT/NPU install. Run AFTER reboot following Section 11a.
# Companion: scripts/lib/11a-xrt-prep.sh.
#
# Steps:
#   1. Pre-checks: 11a was completed, render+video groups now active
#   2. Install 4 XRT .deb files (--fix-broken handles missing deps)
#   3. Add `source /opt/xilinx/xrt/setup.sh` to ~/.bashrc (idempotent)
#   4. Configure /etc/security/limits.d for memlock unlimited (per AMD docs)
#   5. Verify install: xrt-smi examine
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly XRT_PREP_STATE_FILE="$HOME/.cache/zenbook-s16-setup/xrt-prep-done"
readonly XRT_INSTALL_STATE_FILE="$HOME/.cache/zenbook-s16-setup/xrt-install-done"
readonly XRT_SETUP_SCRIPT="/opt/xilinx/xrt/setup.sh"
readonly LIMITS_FILE="/etc/security/limits.d/99-amdxdna.conf"

: "${XRT_BUNDLE_DIR:=$HOME/Downloads/xrt-bundle}"

run_section_11b_xrt_install() {
    log "=== Section 11b: XRT install (post-reboot phase) ==="

    if [[ -f "$XRT_INSTALL_STATE_FILE" ]]; then
        success "Section 11b already completed — re-run --section 11b-verify if you want to re-test"
        return 0
    fi

    # Stage C calls 11b unconditionally; if 11a never ran (no bundle yet), skip silently.
    if [[ "${XRT_SKIP_IF_BUNDLE_MISSING:-0}" == "1" ]] && [[ ! -f "$XRT_PREP_STATE_FILE" ]]; then
        warn "Section 11a not completed (no XRT bundle?) — skipping Section 11b"
        warn "  Once you have the bundle: ./scripts/setup.sh --section 11a, reboot, then --section 11b"
        return 0
    fi

    _xrtb_pre_checks || return 1
    _xrtb_install_xrt_debs || return 1
    _xrtb_setup_bashrc || return 1
    _xrtb_setup_memlock || return 1
    _xrtb_verify || return 1

    if [[ "$DRY_RUN" != "true" ]]; then
        ensure_dir "$(dirname "$XRT_INSTALL_STATE_FILE")"
        date -Iseconds > "$XRT_INSTALL_STATE_FILE"
    fi

    success "Section 11b complete"
    cat <<EOF

────────────────────────────────────────────────────────────────────────────
✓  XRT NPU stack installed.

Next steps:
  - Open a fresh terminal (~/.bashrc updated with XRT setup)
  - Verify NPU:                  zenbook-validate
  - Manual deep check:           sudo /opt/xilinx/xrt/bin/xrt-smi examine
  - PCI device:                  lspci -d 1022: | grep -i signal
  - Kernel module:               lsmod | grep amdxdna
  - DRM accel:                   ls -la /dev/accel/
  - dmesg:                       sudo dmesg | grep -E "amdxdna|NPU"
────────────────────────────────────────────────────────────────────────────

EOF
}

_xrtb_pre_checks() {
    local fatal=0

    if [[ ! -f "$XRT_PREP_STATE_FILE" ]]; then
        error "Section 11a not completed. Run --section 11a first, then reboot, then this section."
        fatal=1
    fi

    # render + video groups must be ACTIVE in current login (post-reboot or newgrp)
    if ! id -nG | grep -qw render; then
        error "Group 'render' not active in current login. Reboot or run 'newgrp render' first."
        fatal=1
    fi
    if ! id -nG | grep -qw video; then
        error "Group 'video' not active in current login. Reboot or run 'newgrp video' first."
        fatal=1
    fi

    # Bundle still present
    if [[ ! -d "$XRT_BUNDLE_DIR" ]]; then
        error "XRT bundle dir gone: $XRT_BUNDLE_DIR"
        fatal=1
    fi

    [[ "$fatal" -eq 1 ]] && return 1
    success "Pre-checks passed: 11a done, render+video active, bundle present"
    return 0
}

_xrtb_install_xrt_debs() {
    # Install order matters: base → base-dev → npu → plugin
    local install_order=(
        "xrt_*_24.04-amd64-base.deb"
        "xrt_*_24.04-amd64-base-dev.deb"
        "xrt_*_24.04-amd64-npu.deb"
        "xrt_plugin*amdxdna.deb"
    )

    for pattern in "${install_order[@]}"; do
        local deb
        deb=$(compgen -G "$XRT_BUNDLE_DIR/$pattern" | head -1)
        if [[ -z "$deb" ]]; then
            error "Missing .deb matching pattern: $pattern"
            return 1
        fi

        log "Installing $(basename "$deb")..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] sudo apt install --fix-broken -y $deb"
            continue
        fi

        if sudo apt install --fix-broken -y "$deb" >>"$LOG_FILE" 2>&1; then
            success "Installed: $(basename "$deb")"
        else
            error "Install failed for: $(basename "$deb")"
            error "  Try manually: sudo apt install --fix-broken -y $deb"
            return 1
        fi
    done

    return 0
}

_xrtb_setup_bashrc() {
    if [[ ! -f "$XRT_SETUP_SCRIPT" ]]; then
        warn "$XRT_SETUP_SCRIPT not found after XRT install — skipping bashrc edit"
        return 0
    fi

    local bashrc="$HOME/.bashrc"
    [[ ! -f "$bashrc" ]] && touch "$bashrc"

    if grep -q "$XRT_SETUP_SCRIPT" "$bashrc"; then
        success "XRT setup line already in ~/.bashrc"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] append XRT lines to ~/.bashrc"
        return 0
    fi

    {
        echo ""
        echo "# Added by zenbook-s16-ubuntu-setup (Section 11b — XRT)"
        echo "# XRT's setup.sh prints verbose env-var dumps + 'autocomplete enabled'"
        echo "# on every shell start — silenced here. Vars still get exported."
        echo "if [[ -f \"$XRT_SETUP_SCRIPT\" ]]; then"
        echo "    export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        # shellcheck disable=SC2129
        echo "    source \"$XRT_SETUP_SCRIPT\" >/dev/null 2>&1"
        echo "fi"
    } >> "$bashrc"

    success "XRT setup added to ~/.bashrc (silent)"
    log "Open a fresh terminal (or run 'source ~/.bashrc') for vars to take effect."
}

_xrtb_setup_memlock() {
    if [[ -f "$LIMITS_FILE" ]] && grep -q "memlock" "$LIMITS_FILE"; then
        success "memlock limits already configured at $LIMITS_FILE"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] write memlock unlimited to $LIMITS_FILE"
        return 0
    fi

    sudo install -m 0755 -d "$(dirname "$LIMITS_FILE")"
    sudo tee "$LIMITS_FILE" >/dev/null <<'EOF'
# Added by zenbook-s16-ubuntu-setup (XRT NPU support)
# Per amd/xdna-driver README: NPU buffer object allocation hits memlock limit
# on default Ubuntu config. Bump to unlimited.
* soft memlock unlimited
* hard memlock unlimited
EOF
    success "memlock limits installed at $LIMITS_FILE"
    warn "Re-login required for memlock change to take effect (already implied by reboot post-11a)"
}

_xrtb_verify() {
    if [[ ! -x /opt/xilinx/xrt/bin/xrt-smi ]]; then
        warn "xrt-smi not found at /opt/xilinx/xrt/bin/ — install may have failed"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] would run xrt-smi examine"
        return 0
    fi

    log "Running xrt-smi examine..."
    local xrt_output
    xrt_output=$(sudo /opt/xilinx/xrt/bin/xrt-smi examine 2>&1) || true
    echo "$xrt_output" | tee -a "$LOG_FILE"

    # Heuristic: presence of "NPU" or "Strix" in output indicates device detected
    if echo "$xrt_output" | grep -qiE "NPU|Strix|amdxdna"; then
        success "NPU device detected by xrt-smi"
    else
        warn "xrt-smi did not report an NPU device. Possible causes:"
        warn "  - amdxdna kernel module not loaded (check: lsmod | grep amdxdna)"
        warn "  - kernel mismatch (uname -r should be 6.17.0-20-generic)"
        warn "  - BIOS NPU disabled — check Advanced → CPU Configuration → IPU"
        warn "  - Run zenbook-validate for a deeper check"
    fi
    return 0
}

#!/usr/bin/env bash
# ============================================================================
# Section 11b — XRT install (post-reboot)
#
# Phase 2 of XRT/NPU install. Run AFTER reboot following Section 11a.
# Companion: scripts/lib/11a-xrt-prep.sh.
#
# Steps:
#   1. Pre-checks: 11a was completed, render+video groups now active
#   2. Install 4 XRT .deb files in a single apt transaction
#   3. Verify DKMS amdxdna built; add modprobe override so DKMS wins over
#      the Linux 6.17 in-kernel stub; reload module live
#   4. Add `source /opt/xilinx/xrt/setup.sh` to ~/.bashrc (idempotent, silent)
#   5. Configure /etc/security/limits.d for memlock unlimited (per AMD docs)
#   6. Verify install: xrt-smi examine
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
    _xrtb_ensure_dkms_amdxdna || warn "DKMS amdxdna setup had issues — xrt-smi validate gemm/throughput may fail (try reboot)"
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
    # Install order matters: base → base-dev → npu → plugin. We pass them all
    # to a SINGLE `apt install` call: apt resolves cross-deps within the
    # transaction (correct order auto-determined). This matches what works
    # reliably when users do `sudo dpkg -i *.deb` manually.
    #
    # Per-file `apt install` (the old approach) sometimes failed because each
    # invocation tried to satisfy the next deb's deps before the previous deb
    # finished registering — cross-package symbols / postinst order issues.
    local install_order=(
        "xrt_*_24.04-amd64-base.deb"
        "xrt_*_24.04-amd64-base-dev.deb"
        "xrt_*_24.04-amd64-npu.deb"
        "xrt_plugin*amdxdna.deb"
    )

    local debs=()
    local pattern
    for pattern in "${install_order[@]}"; do
        local deb
        deb=$(compgen -G "$XRT_BUNDLE_DIR/$pattern" | head -1)
        if [[ -z "$deb" ]]; then
            error "Missing .deb matching pattern: $pattern"
            return 1
        fi
        debs+=("$deb")
        log "  resolved: $(basename "$deb")"
    done

    log "Installing 4 XRT .deb files in a single apt transaction..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo apt install --fix-broken -y ${debs[*]}"
        return 0
    fi

    if sudo apt install --fix-broken -y "${debs[@]}" >>"$LOG_FILE" 2>&1; then
        success "Installed all 4 XRT .deb files"
    else
        error "XRT install failed. Check $LOG_FILE for the apt output."
        error "  Try manually: sudo apt install --fix-broken -y ${debs[*]}"
        return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# Verify the DKMS amdxdna module built successfully AND is the one actually
# loaded — not the older "in-kernel" stub that ships with linux-modules-6.17.
#
# Why this matters: Linux 6.17 mainline ships an amdxdna driver at
# /lib/modules/<kernel>/kernel/drivers/accel/amdxdna/amdxdna.ko version
# 0.0.0. It opens the device fine and supports basic ioctls (`xrt-smi
# examine` works, latency test passes), but lacks the HWCTX configurations
# the gemm and throughput validate tests need. Result: `xrt-smi validate`
# shows two FAILED tests with `DRM_IOCTL_AMDXDNA_CONFIG_HWCTX IOCTL failed
# (err=-95): Operation not supported`.
#
# The xrt_plugin*amdxdna.deb ships a DKMS-built amdxdna with the full
# feature set. We need to:
#   1. Confirm DKMS xrt-driver is registered and built for the running kernel
#   2. Add a modprobe `override` rule so the DKMS version wins over in-kernel
#   3. update-initramfs so the rule is honored at early boot
#   4. Unload + reload amdxdna so the change takes effect without reboot
# ----------------------------------------------------------------------------
_xrtb_ensure_dkms_amdxdna() {
    local rule_file="/etc/modprobe.d/zenbook-s16-amdxdna-dkms.conf"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] would verify DKMS amdxdna build + add modprobe override + reload"
        return 0
    fi

    if ! command -v dkms &>/dev/null; then
        warn "dkms command not found — cannot verify DKMS amdxdna build"
        return 0
    fi

    # 1. Confirm DKMS registered xrt-driver (or any xdna-flavored module)
    local dkms_match
    dkms_match=$(dkms status 2>/dev/null | grep -iE "xrt|xdna" || true)
    if [[ -z "$dkms_match" ]]; then
        warn "No DKMS xrt/xdna entry found — xrt_plugin*amdxdna.deb postinst may have failed"
        warn "  Inspect: sudo cat /var/lib/dkms/*/build/make.log | tail"
        return 1
    fi
    log "DKMS amdxdna registered: $dkms_match"

    # 2. Confirm a built .ko exists under /lib/modules/<kernel>/updates/
    local kver dkms_ko
    kver=$(uname -r)
    dkms_ko=$(sudo find "/lib/modules/${kver}/updates" -name "amdxdna.ko*" 2>/dev/null | head -1)
    if [[ -z "$dkms_ko" ]]; then
        log "DKMS amdxdna not built for $kver yet — running dkms autoinstall..."
        sudo dkms autoinstall -k "$kver" >>"$LOG_FILE" 2>&1 \
            || warn "dkms autoinstall returned non-zero"
        dkms_ko=$(sudo find "/lib/modules/${kver}/updates" -name "amdxdna.ko*" 2>/dev/null | head -1)
        if [[ -z "$dkms_ko" ]]; then
            error "DKMS amdxdna build failed for $kver"
            error "  Check: sudo cat /var/lib/dkms/*/build/make.log | tail"
            return 1
        fi
    fi
    success "DKMS amdxdna built at: $dkms_ko"

    # 3. Add modprobe override rule (DKMS wins over in-kernel on next boot)
    if [[ ! -f "$rule_file" ]]; then
        log "Writing modprobe override: prefer DKMS amdxdna over in-kernel"
        sudo tee "$rule_file" >/dev/null <<'EOF'
# Generated by zenbook-s16-ubuntu-setup (Section 11b)
#
# Linux 6.17 mainline ships amdxdna 0.0.0 at:
#   /lib/modules/<kernel>/kernel/drivers/accel/amdxdna/amdxdna.ko
# That stub driver supports basic ioctls only. The full-feature DKMS build
# from xrt_plugin*amdxdna.deb (needed for HWCTX configs, gemm, throughput)
# lives at:
#   /lib/modules/<kernel>/updates/dkms/amdxdna.ko
# This `override` rule tells modprobe to load the `updates` one preferentially.
override amdxdna * updates
EOF
        sudo update-initramfs -u >>"$LOG_FILE" 2>&1 \
            || warn "update-initramfs returned non-zero"
        success "modprobe override rule added at $rule_file"
    else
        log "modprobe override rule already in place at $rule_file"
    fi

    # 4. Reload amdxdna live (avoids needing another reboot)
    local loaded_path
    if lsmod | grep -q "^amdxdna"; then
        loaded_path=$(modinfo amdxdna 2>/dev/null | awk '/^filename:/ {print $2}')
        if [[ "$loaded_path" == *"/updates/"* ]]; then
            success "DKMS amdxdna already the loaded version ($loaded_path)"
            return 0
        fi
        log "In-kernel amdxdna currently loaded ($loaded_path) — switching to DKMS"
        if ! sudo modprobe -r amdxdna 2>>"$LOG_FILE"; then
            warn "Failed to unload in-kernel amdxdna (device busy?). Reboot to apply override."
            return 0
        fi
    fi
    if sudo modprobe amdxdna 2>>"$LOG_FILE"; then
        loaded_path=$(modinfo amdxdna 2>/dev/null | awk '/^filename:/ {print $2}')
        if [[ "$loaded_path" == *"/updates/"* ]]; then
            success "DKMS amdxdna now loaded: $loaded_path"
        else
            warn "amdxdna re-loaded but path is $loaded_path (expected /updates/...). Reboot recommended."
        fi
    else
        warn "modprobe amdxdna failed after unload — try reboot"
        return 1
    fi
    return 0
}

_xrtb_setup_bashrc() {
    if [[ ! -f "$XRT_SETUP_SCRIPT" ]]; then
        warn "$XRT_SETUP_SCRIPT not found after XRT install — skipping bashrc edit"
        return 0
    fi

    local bashrc="$HOME/.bashrc"
    [[ ! -f "$bashrc" ]] && touch "$bashrc"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] append/update XRT lines in ~/.bashrc"
        return 0
    fi

    # Migration (v0.3.11): older versions prepended /lib/x86_64-linux-gnu to
    # LD_LIBRARY_PATH before sourcing XRT setup.sh. That overrides RUNPATH in
    # ROCm binaries, causing them to load the system-packaged libhsa-runtime64
    # instead of /opt/rocm/lib's version → HSA_STATUS_ERROR_INVALID_ARGUMENT
    # from rocminfo, clinfo, and any HIP application.
    if grep -q 'LD_LIBRARY_PATH=/lib/x86_64-linux-gnu' "$bashrc"; then
        sed -i '/export LD_LIBRARY_PATH=\/lib\/x86_64-linux-gnu/d' "$bashrc"
        success "Removed stale LD_LIBRARY_PATH=/lib/x86_64-linux-gnu from ~/.bashrc (ROCm coexistence fix)"
    fi

    if grep -q "$XRT_SETUP_SCRIPT" "$bashrc"; then
        # XRT source line already present. Ensure the /opt/rocm/lib priority fix is also there.
        if ! grep -q '/opt/rocm/lib' "$bashrc"; then
            cat >> "$bashrc" <<'ROCM_FIX'

# Added by zenbook-s16-ubuntu-setup v0.3.11+ (ROCm/XRT LD_LIBRARY_PATH fix)
# Ensure ROCm's libhsa-runtime64 takes precedence over the system-packaged one.
# XRT setup.sh prepends /opt/xilinx/xrt/lib to LD_LIBRARY_PATH; without this,
# LD_LIBRARY_PATH overrides RUNPATH in ROCm binaries, loading the wrong
# libhsa-runtime64 and causing HSA_STATUS_ERROR_INVALID_ARGUMENT.
export LD_LIBRARY_PATH=/opt/rocm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
ROCM_FIX
            success "Added /opt/rocm/lib priority to ~/.bashrc (ROCm/XRT coexistence fix)"
        else
            success "XRT setup already in ~/.bashrc (with ROCm fix)"
        fi
        return 0
    fi

    {
        echo ""
        echo "# Added by zenbook-s16-ubuntu-setup (Section 11b — XRT)"
        echo "# XRT's setup.sh prints verbose env-var dumps + 'autocomplete enabled'"
        echo "# on every shell start — silenced here. Vars still get exported."
        echo "if [[ -f \"$XRT_SETUP_SCRIPT\" ]]; then"
        echo "    source \"$XRT_SETUP_SCRIPT\" >/dev/null 2>&1"
        echo "    # Ensure ROCm's libhsa-runtime64 takes precedence over the system-packaged"
        echo "    # version. XRT setup.sh sets LD_LIBRARY_PATH; without /opt/rocm/lib first,"
        echo "    # LD_LIBRARY_PATH overrides RUNPATH in ROCm binaries → wrong libhsa-runtime64"
        echo "    # → HSA_STATUS_ERROR_INVALID_ARGUMENT from rocminfo / HIP applications."
        echo "    export LD_LIBRARY_PATH=/opt/rocm/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
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

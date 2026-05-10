#!/usr/bin/env bash
# ============================================================================
# Stage runners - _run_stage_A / B / C
#
# Stages are opinionated "bundle" entry points. Each stage runs a fixed set
# of sections and ends with a banner telling the user what to do next
# (typically: reboot, then re-run with the next stage).
#
# Reboot points correspond to natural hardware/system events:
#   A → reboot to activate kernel 6.17.0-20-generic
#   B → reboot to activate render/video group membership for amdxdna
#   C → no reboot (XRT install + long mise builds), run zenbook-validate
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# TARGET_KERNEL ("6.17.0-20") is exported by 02-kernel-pin.sh (sourced before
# stages.sh in setup.sh). We append "-generic" to compose the full uname.
# The XRT download portal URL lives in docs/09-xrt-stack.md (too long to fit
# cleanly in the 76-col banner); banners just reference the doc.

# ----------------------------------------------------------------------------
# Stage A - preflight + kernel pin
# ----------------------------------------------------------------------------
_run_stage_A() {
    log "===== STAGE A: preflight + kernel pin ====="

    run_section_01_preflight  || { error "Pre-flight failed - aborting Stage A"; exit 1; }
    run_section_02_kernel_pin || warn "Section 02 had errors (kernel pin)"

    # Decide which banner variant to print:
    #   1. GRUB fix needed   → kernel installed but GRUB default not set
    #   2. No reboot needed  → already running target kernel
    #   3. Reboot now        → target kernel installed + GRUB default set
    local current_kernel
    current_kernel="$(uname -r)"
    local grub_fail_marker="$HOME/.cache/zenbook-s16-setup/sec02-grub-fix-needed"
    if [[ -f "$grub_fail_marker" ]]; then
        print_banner \
            "S T A G E   A   .   M A N U A L   G R U B   F I X   N E E D E D" \
            "> Kernel ${TARGET_KERNEL}-generic is installed and held," \
            "  but GRUB_DEFAULT could not be set automatically." \
            "  (See errors above for the awk strategies that failed.)" \
            "" \
            "> Quickest fix (works on Ubuntu 24.04 default GRUB layout):" \
            "" \
            "    sudo sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options\\\\" \
            "        for Ubuntu>Ubuntu, with Linux ${TARGET_KERNEL}-generic\"|' \\\\" \
            "        /etc/default/grub" \
            "    sudo update-grub" \
            "    sudo reboot" \
            "" \
            "> Or at GRUB boot menu, pick manually:" \
            "      Advanced options for Ubuntu  >  ${TARGET_KERNEL}-generic" \
            "" \
            "> Detailed steps + how to inspect grub.cfg:" \
            "      docs/02-kernel-pinning.md  (\"Manual GRUB fix\" section)" \
            "" \
            "> After uname -r shows ${TARGET_KERNEL}-generic, continue with --stage B." \
            "  Re-running --stage A is safe (idempotent)."
        return 0
    fi
    if [[ "$current_kernel" == "${TARGET_KERNEL}-generic" ]]; then
        print_banner \
            "S T A G E   A   .   D O N E   .   N O   R E B O O T   N E E D E D" \
            "> Already running the target kernel: $current_kernel" \
            "" \
            "> Next step:" \
            "    ./scripts/setup.sh --stage B" \
            "" \
            "> Heads-up - if you plan to use the NPU, fetch the XRT bundle" \
            "  during Stage B prep. EULA-gated; cannot auto-download." \
            "  Portal:    AMD Ryzen AI Software (URL in docs/09-xrt-stack.md)" \
            "  Place 4 .deb files into ~/Downloads/xrt-bundle/"
    else
        print_banner \
            "S T A G E   A   .   D O N E   .   R E B O O T   N O W" \
            "> Currently booted: $current_kernel" \
            "> Need to boot:     ${TARGET_KERNEL}-generic  (installed + held)" \
            "" \
            "> After reboot, run:" \
            "    ./scripts/setup.sh --stage B" \
            "" \
            "> While rebooting, download the XRT bundle (needed for NPU)" \
            "  from AMD Ryzen AI Software portal (URL in docs/09-xrt-stack.md)." \
            "  Extract .tgz; place 4 .deb files into ~/Downloads/xrt-bundle/ :" \
            "      xrt_*_24.04-amd64-base.deb" \
            "      xrt_*_24.04-amd64-base-dev.deb" \
            "      xrt_*_24.04-amd64-npu.deb" \
            "      xrt_plugin*amdxdna.deb"
    fi
}

# ----------------------------------------------------------------------------
# Stage B - apt + apps + steam + xrt prep
# ----------------------------------------------------------------------------
_run_stage_B() {
    log "===== STAGE B: apt + apps + steam + XRT prep ====="

    # Sanity: warn (don't abort) if not on target kernel
    local current_kernel
    current_kernel="$(uname -r)"
    if [[ "$current_kernel" != "${TARGET_KERNEL}-generic" ]]; then
        warn "Currently on kernel $current_kernel, expected ${TARGET_KERNEL}-generic"
        warn "  XRT prep (sec 11a) will fail or skip. Re-run Stage A + reboot if NPU is needed."
    fi

    run_section_03_apt_base       || warn "Section 03 had errors (apt base)"
    run_section_04_apt_extended   || warn "Section 04 had errors (apt extended)"
    run_section_05_dev_toolchain  || warn "Section 05 had errors (dev toolchain)"
    run_section_06_ai_stack       || warn "Section 06 had errors (AI stack)"
    run_section_07_apps_stack     || warn "Section 07 had errors (apps)"
    run_section_08_flatpak_apps   || warn "Section 08 had errors (flatpak apps)"
    run_section_09_gaming         || warn "Section 09 had errors (gaming)"

    # XRT prep: graceful skip if bundle missing, since Stage B is the
    # opinionated "include all" path. The user re-runs --section 11a after
    # they have the bundle.
    XRT_SKIP_IF_BUNDLE_MISSING=1 run_section_11a_xrt_prep \
        || warn "Section 11a (XRT prep) had errors"

    # Decide reboot messaging based on whether 11a actually completed
    local xrt_prep_marker="$HOME/.cache/zenbook-s16-setup/xrt-prep-done"
    if [[ -f "$xrt_prep_marker" ]]; then
        print_banner \
            "S T A G E   B   .   D O N E   .   R E B O O T   N O W" \
            "> Reboot to activate render/video group membership" \
            "  (required for the amdxdna NPU driver to be usable)." \
            "" \
            "> After reboot, run:" \
            "    ./scripts/setup.sh --stage C" \
            "" \
            "> Stage C will:" \
            "    * Install the 4 XRT .deb files (sec 11b)" \
            "    * Install 8 mise default languages (sec 12, ~30 min for Erlang)" \
            "    * Generate zenbook-validate (sec 10)" \
            "" \
            "> Tip: skip the long Erlang build with:" \
            "    ZENBOOK_SKIP_MISE_DEFAULTS=1 ./scripts/setup.sh --stage C"
    else
        print_banner \
            "S T A G E   B   .   D O N E   .   X R T   S K I P P E D" \
            "> XRT bundle was not found at: ~/Downloads/xrt-bundle/" \
            "  Section 11a (NPU prep) was skipped." \
            "" \
            "> If you want NPU support:" \
            "    1. Get bundle from AMD Ryzen AI Software portal" \
            "       (EULA-gated; URL + filenames in docs/09-xrt-stack.md)" \
            "    2. Extract + place 4 .deb files into ~/Downloads/xrt-bundle/" \
            "    3. Run:    ./scripts/setup.sh --section 11a" \
            "    4. Reboot, then continue with Stage C" \
            "" \
            "> If you don't need the NPU, just run:" \
            "    ./scripts/setup.sh --stage C"
    fi
}

# ----------------------------------------------------------------------------
# Stage C - xrt install + mise defaults + validate generation
# ----------------------------------------------------------------------------
_run_stage_C() {
    log "===== STAGE C: XRT install + mise langs + validate ====="

    # XRT install: graceful skip if 11a never completed (no bundle / Stage B
    # skipped XRT). The marker check inside 11b will warn and return 0.
    XRT_SKIP_IF_BUNDLE_MISSING=1 run_section_11b_xrt_install \
        || warn "Section 11b (XRT install) had errors"

    # Mise default languages - opt-out via env var (long-running due to Erlang)
    if [[ "${ZENBOOK_SKIP_MISE_DEFAULTS:-0}" == "1" ]]; then
        warn "Section 12 (mise defaults) skipped via ZENBOOK_SKIP_MISE_DEFAULTS=1"
    else
        log "Section 12 (mise defaults) - this can take 15-30 minutes (Erlang OTP build)"
        run_section_12_mise_defaults || warn "Section 12 (mise defaults) had errors"
    fi

    # Generate (only) the zenbook-validate script - do not auto-run.
    # The EXIT trap also calls this; explicit call makes the order clear in logs.
    run_section_10_validate || warn "Section 10 (validate script gen) had errors"

    print_banner \
        "S T A G E   C   .   D O N E   .   S E T U P   C O M P L E T E" \
        "> Run validation to confirm everything is healthy:" \
        "    zenbook-validate" \
        "" \
        "> Then sign in / configure:" \
        "    * 1Password (desktop + browser ext)" \
        "    * LocalSend (pair with another device on same WiFi)" \
        "    * Cursor    (login or BYO key)" \
        "    * claude login    (Claude Code CLI)" \
        "    * gh auth login   (GitHub CLI)" \
        "" \
        "> Re-login (or: newgrp docker) so Docker group membership takes effect." \
        "" \
        "> Docs: docs/07-validation.md  +  docs/08-troubleshooting.md"
}

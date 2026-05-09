#!/usr/bin/env bash
# ============================================================================
# zenbook-s16-ubuntu-setup — main entrypoint
#
# Usage:
#   ./scripts/setup.sh [--dry-run] [--with-ai-stack] [--with-apps]
#                      [--with-flatpak] [--with-gaming]
#                      [--section N] [--help]
#
# Default: runs sections 01–05 (preflight, kernel pin, apt base, apt extended,
# dev toolchain) + validation. Optional opt-in flags pull in 06–09.
#
# Sections:
#   01  Pre-flight checks
#   02  Kernel pinning (amdxdna NPU fix)
#   03  Base APT packages
#   04  Extended APT (libs + Vulkan/Mesa + system monitor)
#   05  Dev toolchain (mise + Docker)
#   06  AI stack (Cursor, Warp, Node.js, Claude Code) — opt-in
#   07  Apps stack (1Password, Chrome, LocalSend, Typora, etc) — opt-in
#   08  Flatpak apps (media + comms + productivity) — opt-in
#   09  Gaming (Steam + ProtonUp-Qt) — opt-in
#   10  Validation script generation (always runs)
# ============================================================================

# Resolve the directory containing this script, then the lib/ folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source common.sh first — gives us all helpers + sets DRY_RUN default
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

# Source all section files
# shellcheck source=lib/01-preflight.sh
source "$LIB_DIR/01-preflight.sh"
# shellcheck source=lib/02-kernel-pin.sh
source "$LIB_DIR/02-kernel-pin.sh"
# shellcheck source=lib/03-apt-base.sh
source "$LIB_DIR/03-apt-base.sh"
# shellcheck source=lib/04-apt-extended.sh
source "$LIB_DIR/04-apt-extended.sh"
# shellcheck source=lib/05-dev-toolchain.sh
source "$LIB_DIR/05-dev-toolchain.sh"
# shellcheck source=lib/06-ai-stack.sh
source "$LIB_DIR/06-ai-stack.sh"
# shellcheck source=lib/07-apps-stack.sh
source "$LIB_DIR/07-apps-stack.sh"
# shellcheck source=lib/08-flatpak-apps.sh
source "$LIB_DIR/08-flatpak-apps.sh"
# shellcheck source=lib/09-gaming.sh
source "$LIB_DIR/09-gaming.sh"
# shellcheck source=lib/10-validate.sh
source "$LIB_DIR/10-validate.sh"

# ----------------------------------------------------------------------------
# Trap: ensure validation script is always generated
# ----------------------------------------------------------------------------
_validation_generated=0
_generate_validation_safe() {
    if [[ "$_validation_generated" == "0" ]]; then
        _validation_generated=1
        run_section_10_validate || true
    fi
}
trap _generate_validation_safe EXIT

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
WITH_AI_STACK=0
WITH_APPS=0
WITH_FLATPAK=0
WITH_GAMING=0
SECTION=""

usage() {
    cat <<'EOF'
zenbook-s16-ubuntu-setup — battle-tested Ubuntu 24.04 setup for ASUS Zenbook S16

USAGE:
    ./scripts/setup.sh [OPTIONS]

OPTIONS:
    --dry-run            Preview commands without executing
    --with-ai-stack      Install Cursor + Warp + Node.js + Claude Code
    --with-apps          Install 1Password + Chrome + LocalSend + Typora +
                         Gum + LazyGit + LazyDocker + Ulauncher
    --with-flatpak       Install Flatpak apps (media + comms + productivity)
    --with-gaming        Install Steam + ProtonUp-Qt
    --all                Shortcut for --with-ai-stack --with-apps --with-flatpak --with-gaming
    --section N          Run only section N (01–10, also accepts numeric: 1–10)
    -h, --help           Show this help

ENVIRONMENT OVERRIDES:
    DRY_RUN=true                     Same as --dry-run
    ZENBOOK_SKIP_KERNEL_PIN=1        Skip section 02 (kernel pinning)
    NO_COLOR=1                       Disable colored output

EXAMPLES:
    # Minimal install (sections 01–05)
    ./scripts/setup.sh

    # Full install
    ./scripts/setup.sh --all

    # Just verify kernel + GPU stack
    ./scripts/setup.sh --section 04

    # Preview what --with-apps would do
    ./scripts/setup.sh --dry-run --with-apps
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=true ;;
        --with-ai-stack)  WITH_AI_STACK=1 ;;
        --with-apps)      WITH_APPS=1 ;;
        --with-flatpak)   WITH_FLATPAK=1 ;;
        --with-gaming)    WITH_GAMING=1 ;;
        --all)
            WITH_AI_STACK=1; WITH_APPS=1; WITH_FLATPAK=1; WITH_GAMING=1 ;;
        --section)
            shift
            SECTION="${1:-}"
            if [[ -z "$SECTION" ]]; then
                error "--section requires an argument (01-10)"
                exit 1
            fi
            ;;
        -h|--help) usage; exit 0 ;;
        *)
            error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# ----------------------------------------------------------------------------
# Main dispatch
# ----------------------------------------------------------------------------
log "============================================"
log "zenbook-s16-ubuntu-setup"
log "Started: $(date)"
log "Log file: $LOG_FILE"
[[ "$DRY_RUN" == "true" ]] && log "Mode: DRY-RUN (no changes will be made)"
log "============================================"

# Normalize section number (accept "1", "01", "5", "05", etc)
_section_num() {
    case "$1" in
        1|01) echo "01" ;;
        2|02) echo "02" ;;
        3|03) echo "03" ;;
        4|04) echo "04" ;;
        5|05) echo "05" ;;
        6|06) echo "06" ;;
        7|07) echo "07" ;;
        8|08) echo "08" ;;
        9|09) echo "09" ;;
        10)   echo "10" ;;
        *)    echo "" ;;
    esac
}

if [[ -n "$SECTION" ]]; then
    norm="$(_section_num "$SECTION")"
    case "$norm" in
        01) run_section_01_preflight ;;
        02) run_section_02_kernel_pin ;;
        03) run_section_03_apt_base ;;
        04) run_section_04_apt_extended ;;
        05) run_section_05_dev_toolchain ;;
        06) run_section_06_ai_stack ;;
        07) run_section_07_apps_stack ;;
        08) run_section_08_flatpak_apps ;;
        09) run_section_09_gaming ;;
        10) run_section_10_validate ;;
        *)
            error "Invalid section: $SECTION (valid: 01-10)"
            exit 1
            ;;
    esac
else
    # Full default flow
    run_section_01_preflight        || { error "Pre-flight failed — aborting"; exit 1; }
    run_section_02_kernel_pin       || warn "Section 02 had errors (kernel pin)"
    run_section_03_apt_base         || warn "Section 03 had errors (apt base)"
    run_section_04_apt_extended     || warn "Section 04 had errors (apt extended)"
    run_section_05_dev_toolchain    || warn "Section 05 had errors (dev toolchain)"

    [[ "$WITH_AI_STACK" == "1" ]] && { run_section_06_ai_stack    || warn "Section 06 had errors"; }
    [[ "$WITH_APPS"     == "1" ]] && { run_section_07_apps_stack  || warn "Section 07 had errors"; }
    [[ "$WITH_FLATPAK"  == "1" ]] && { run_section_08_flatpak_apps || warn "Section 08 had errors"; }
    [[ "$WITH_GAMING"   == "1" ]] && { run_section_09_gaming       || warn "Section 09 had errors"; }
fi

log "============================================"
log "Setup finished: $(date)"
log "Log file: $LOG_FILE"
log "============================================"

if [[ "$DRY_RUN" != "true" ]]; then
    cat <<EOF

────────────────────────────────────────────────────────────────────────────
Manual follow-up steps:

  1. **Reboot** if section 02 (kernel pin) installed a new kernel.
     Verify after reboot:    uname -r       (should be 6.17.0-20-generic)

  2. **Re-login** so 'docker' group membership takes effect.
     Or run:                 newgrp docker

  3. **Run validation:**     zenbook-validate

  4. (Optional) Sign in / configure:
     - 1Password desktop  +  browser extension
     - LocalSend (pair with another device on same WiFi)
     - Cursor             (login to Cursor / use BYO key)
     - claude login       (Claude Code CLI)
     - gh auth login      (GitHub CLI)

See docs/07-validation.md and docs/08-troubleshooting.md for more.
────────────────────────────────────────────────────────────────────────────
EOF
fi

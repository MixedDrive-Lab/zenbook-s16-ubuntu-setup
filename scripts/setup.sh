#!/usr/bin/env bash
# ============================================================================
# zenbook-s16-ubuntu-setup — main entrypoint
#
# Usage:
#   ./scripts/setup.sh --stage A|B|C [--dry-run]
#   ./scripts/setup.sh --section N    [--dry-run]    (granular escape hatch)
#   ./scripts/setup.sh --help
#
# Three-stage flow (recommended path):
#
#   Stage A: 01 preflight + 02 kernel pin → REBOOT (kernel 6.17.0-20-generic)
#   Stage B: 03–09 (apt + apps + flatpak + steam) + 11a XRT prep → REBOOT
#   Stage C: 11b XRT install + 12 mise default languages
#            (10 validate script generated; run zenbook-validate manually)
#
# Sections (for --section escape hatch):
#   01  Pre-flight checks
#   02  Kernel pinning (amdxdna NPU fix)
#   03  Base APT packages (incl. flatpak runtime)
#   04  Extended APT (libs + Vulkan/Mesa + system monitor)
#   05  Dev toolchain (mise + Docker)
#   06  AI stack (Cursor, Warp, Node.js, Claude Code)
#   07  Apps stack (1Password, Chrome, LocalSend, Typora, etc)
#   08  Flatpak apps (media + comms + productivity)
#   09  Gaming (Steam + ProtonUp-Qt)
#   10  Validation script generation
#   11a XRT NPU prep (amdgpu-install + ROCm + groups, pre-reboot)
#   11b XRT NPU install (XRT debs + verify, post-reboot)
#   12  mise default languages (Python/Node/Go/Java/Ruby/Erlang/Elixir/PHP/Rust)
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
# shellcheck source=lib/11a-xrt-prep.sh
source "$LIB_DIR/11a-xrt-prep.sh"
# shellcheck source=lib/11b-xrt-install.sh
source "$LIB_DIR/11b-xrt-install.sh"
# shellcheck source=lib/12-mise-defaults.sh
source "$LIB_DIR/12-mise-defaults.sh"
# shellcheck source=lib/10-validate.sh
source "$LIB_DIR/10-validate.sh"
# shellcheck source=lib/stages.sh
source "$LIB_DIR/stages.sh"

# ----------------------------------------------------------------------------
# Trap: ensure validation script is always generated (idempotent)
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
STAGE=""
SECTION=""

usage() {
    cat <<'EOF'
zenbook-s16-ubuntu-setup — battle-tested Ubuntu 24.04 setup for ASUS Zenbook S16

USAGE:
    ./scripts/setup.sh --stage A|B|C [OPTIONS]
    ./scripts/setup.sh --section N   [OPTIONS]

STAGES (recommended):
    --stage A     Sections 01–02 (preflight + kernel pin → reboot)
    --stage B     Sections 03–09 + 11a (apt + apps + steam + XRT prep → reboot)
    --stage C     Sections 11b + 12 + 10 (XRT install + mise langs + validate gen)

OPTIONS:
    --dry-run            Preview commands without executing
                         (curl/ca-certs/gnupg are still installed for real
                         since they are dry-run prerequisites)
    --xrt-bundle-dir DIR Override location of XRT bundle
                         (default ~/Downloads/xrt-bundle)
                         Same as XRT_BUNDLE_DIR env.
    --section N          Run only section N (escape hatch for re-runs / debug;
                         valid: 01–10, 11a, 11b, 12)
    -h, --help           Show this help

ENVIRONMENT OVERRIDES:
    DRY_RUN=true                     Same as --dry-run
    ZENBOOK_SKIP_KERNEL_PIN=1        Skip section 02 (kernel pinning)
    ZENBOOK_SKIP_MISE_DEFAULTS=1     Skip section 12 in Stage C (saves ~30 min
                                     of Erlang OTP build)
    XRT_BUNDLE_DIR=/path/to/dir      Same as --xrt-bundle-dir
    NO_COLOR=1                       Disable colored output

EXAMPLES:
    # Recommended flow — three stages with reboots in between:
    ./scripts/setup.sh --stage A     # 01-02; reboot when done
    sudo reboot
    ./scripts/setup.sh --stage B     # 03-09 + 11a; reboot when done
    sudo reboot
    ./scripts/setup.sh --stage C     # 11b + 12 + 10
    zenbook-validate                 # final verification

    # Preview a stage without changes
    ./scripts/setup.sh --dry-run --stage B

    # Re-run a single section (e.g. after fixing an issue)
    ./scripts/setup.sh --section 11a

    # Skip the long Erlang build in Stage C
    ZENBOOK_SKIP_MISE_DEFAULTS=1 ./scripts/setup.sh --stage C

XRT NPU NOTES:
    Stage B includes XRT prep (sec 11a) which needs 4 EULA-gated .deb files
    in ~/Downloads/xrt-bundle/. Stage A prints a heads-up so you can download
    them while the machine reboots.

    Download from:
      https://www.amd.com/en/developer/resources/ryzen-ai-software.html
EOF
}

# Helper: clean exit on argument errors (suppress validate-gen trap noise)
_arg_error() {
    error "$1"
    [[ "${2:-}" == "showhelp" ]] && { echo; usage; }
    trap - EXIT
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=true ;;
        --stage)
            shift
            STAGE="${1:-}"
            [[ -z "$STAGE" ]] && _arg_error "--stage requires an argument (A, B, or C)"
            ;;
        --xrt-bundle-dir)
            shift
            [[ -z "${1:-}" ]] && _arg_error "--xrt-bundle-dir requires a path argument"
            export XRT_BUNDLE_DIR="$1"
            ;;
        --section)
            shift
            SECTION="${1:-}"
            [[ -z "$SECTION" ]] && _arg_error "--section requires an argument (01-10, 11a, 11b, 12)"
            ;;
        -h|--help) usage; trap - EXIT; exit 0 ;;
        *)
            _arg_error "Unknown argument: $1" showhelp
            ;;
    esac
    shift
done

if [[ -z "$STAGE" && -z "$SECTION" ]]; then
    _arg_error "Must specify --stage A|B|C or --section N" showhelp
fi

if [[ -n "$STAGE" && -n "$SECTION" ]]; then
    _arg_error "--stage and --section are mutually exclusive"
fi

# Validate stage value before any side effects
if [[ -n "$STAGE" ]]; then
    case "$(printf '%s' "$STAGE" | tr '[:lower:]' '[:upper:]')" in
        A|B|C) ;;
        *) _arg_error "Invalid --stage: '$STAGE' (must be A, B, or C)" ;;
    esac
fi

# ----------------------------------------------------------------------------
# Main dispatch
# ----------------------------------------------------------------------------
log "============================================"
log "zenbook-s16-ubuntu-setup"
log "Started: $(date)"
log "Log file: $LOG_FILE"
[[ "$DRY_RUN" == "true" ]] && log "Mode: DRY-RUN (no changes will be made)"
[[ -n "$STAGE"   ]] && log "Stage: $STAGE"
[[ -n "$SECTION" ]] && log "Section: $SECTION"
log "============================================"

# Bootstrap minimal deps (needed even for --dry-run, since preflight uses curl)
bootstrap_minimal_deps || { error "Bootstrap failed — fix sudo/network and retry"; exit 1; }

# ----------------------------------------------------------------------------
# Section dispatch (escape hatch)
# ----------------------------------------------------------------------------
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
        11a) echo "11a" ;;
        11b) echo "11b" ;;
        12)   echo "12" ;;
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
        11a) run_section_11a_xrt_prep ;;
        11b) run_section_11b_xrt_install ;;
        12) run_section_12_mise_defaults ;;
        *)
            error "Invalid section: $SECTION (valid: 01-10, 11a, 11b, 12)"
            exit 1
            ;;
    esac
    log "============================================"
    log "Section $SECTION finished: $(date)"
    log "============================================"
    exit 0
fi

# ----------------------------------------------------------------------------
# Stage dispatch
# ----------------------------------------------------------------------------
case "$(printf '%s' "$STAGE" | tr '[:lower:]' '[:upper:]')" in
    A) _run_stage_A ;;
    B) _run_stage_B ;;
    C) _run_stage_C ;;
    *)
        error "Invalid --stage: $STAGE (must be A, B, or C)"
        exit 1
        ;;
esac

log "============================================"
log "Setup finished: $(date)"
log "Log file: $LOG_FILE"
log "============================================"

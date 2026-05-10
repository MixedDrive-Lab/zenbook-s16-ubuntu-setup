#!/usr/bin/env bash
# ============================================================================
# Standalone validation entry point.
#
# Generates ~/.local/bin/zenbook-validate (re-runs section 10) and then
# executes it immediately so you can see the result without a separate step.
#
# After the first run, you can just type `zenbook-validate` from anywhere.
# ============================================================================

usage() {
    cat <<'EOF'
zenbook-validate generator + runner

USAGE:
    ./scripts/validate.sh [--help]

This script has no flags. It (re)generates ~/.local/bin/zenbook-validate
from the current section-10 logic, then runs it. Use it after editing
scripts/lib/10-validate.sh, or just to re-check system health.

The generated `zenbook-validate` is also created automatically at the end
of every `./scripts/setup.sh` run via an EXIT trap.

After installation, run:
    zenbook-validate
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "")        ;;  # no args — proceed
    *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/10-validate.sh
source "$SCRIPT_DIR/lib/10-validate.sh"

run_section_10_validate

# Run it now if we just generated it
if [[ -x "$HOME/.local/bin/zenbook-validate" ]]; then
    echo ""
    "$HOME/.local/bin/zenbook-validate"
fi

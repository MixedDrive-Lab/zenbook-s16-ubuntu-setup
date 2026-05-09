#!/usr/bin/env bash
# ============================================================================
# Standalone validation entry point.
# Generates ~/.local/bin/zenbook-validate and runs it.
# ============================================================================

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

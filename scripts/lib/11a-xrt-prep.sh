#!/usr/bin/env bash
# ============================================================================
# Section 11a — XRT prep (amdgpu-install + ROCm + groups)
#
# Phase 1 of the XRT/NPU install. Pre-reboot.
# Companion: scripts/lib/11b-xrt-install.sh (post-reboot phase).
#
# Steps:
#   1. Pre-checks: kernel 6.17.0-20-generic booted, apt hold active
#   2. Locate XRT bundle dir (default ~/Downloads/xrt-bundle, override
#      via XRT_BUNDLE_DIR env or --xrt-bundle-dir flag)
#   3. Auto-download amdgpu-install_*.deb from repo.radeon.com if missing
#      (it's public, MIT-friendly; the XRT .deb files are EULA-gated and
#      must be provided by the user)
#   4. Install amdgpu-install_*.deb
#   5. Run `amdgpu-install --usecase=rocm,hiplibsdk --no-dkms -y --accept-eula`
#      (--no-dkms is critical — we keep the held HWE kernel's amdxdna)
#   6. Add user to render + video groups
#   7. Print reboot banner — user must reboot before running 11b
#
# Reference docs:
#   - https://repo.radeon.com/amdgpu-install/latest/ubuntu/noble/
#   - https://ryzenai.docs.amd.com/en/latest/linux.html
#   - https://www.amd.com/en/developer/resources/ryzen-ai-software.html
# ============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly XRT_REQUIRED_KERNEL="6.17.0-20-generic"
readonly AMDGPU_INSTALL_INDEX="https://repo.radeon.com/amdgpu-install/latest/ubuntu/noble/"
readonly XRT_STATE_FILE="$HOME/.cache/zenbook-s16-setup/xrt-prep-done"

# XRT_BUNDLE_DIR overridable via env; default to ~/Downloads/xrt-bundle
: "${XRT_BUNDLE_DIR:=$HOME/Downloads/xrt-bundle}"

run_section_11a_xrt_prep() {
    log "=== Section 11a: XRT prep (amdgpu-install + ROCm + groups) ==="

    if [[ -f "$XRT_STATE_FILE" ]]; then
        success "Section 11a already completed (state file: $XRT_STATE_FILE)"
        log "If this is wrong, delete the state file and re-run."
        log "Next step: reboot, then run --section 11b"
        return 0
    fi

    _xrt_pre_checks || return 1
    _xrt_repair_amd_repos || warn "AMD repo auto-repair had issues — proceeding (amdgpu-install may report errors)"
    if ! _xrt_locate_bundle; then
        # When called from Stage B (XRT_SKIP_IF_BUNDLE_MISSING=1), missing bundle
        # is not a hard failure — Stage B is opinionated "include all if available".
        # Re-run --section 11a manually after the user downloads the bundle.
        if [[ "${XRT_SKIP_IF_BUNDLE_MISSING:-0}" == "1" ]]; then
            warn "XRT bundle missing — skipping Section 11a (re-run --section 11a after download)"
            return 0
        fi
        return 1
    fi
    _xrt_install_amdgpu_install || return 1
    _xrt_run_amdgpu_install || return 1
    _xrt_add_user_groups || return 1

    # Mark section done
    if [[ "$DRY_RUN" != "true" ]]; then
        ensure_dir "$(dirname "$XRT_STATE_FILE")"
        date -Iseconds > "$XRT_STATE_FILE"
    fi

    success "Section 11a complete"
    cat <<EOF

────────────────────────────────────────────────────────────────────────────
⚠  REBOOT REQUIRED before continuing.

  1. Reboot:                     sudo reboot
  2. After reboot, verify:       groups | grep -E 'render|video'
  3. Then run Section 11b:       ./scripts/setup.sh --section 11b
                                    OR
                                  ./scripts/setup.sh --with-xrt
                                  (will auto-skip 11a, run 11b)
────────────────────────────────────────────────────────────────────────────

EOF
}

_xrt_pre_checks() {
    local fatal=0

    # Kernel must be 6.17.0-20-generic
    local current
    current=$(uname -r)
    if [[ "$current" != "$XRT_REQUIRED_KERNEL" ]]; then
        error "XRT NPU stack requires kernel $XRT_REQUIRED_KERNEL"
        error "  Currently booted: $current"
        error "  Run Section 02 (kernel pin) first, reboot, then retry."
        fatal=1
    else
        success "Kernel: $current (matches required $XRT_REQUIRED_KERNEL)"
    fi

    # apt-hold must be active
    if ! apt-mark showhold 2>/dev/null | grep -q "^linux-image-generic"; then
        warn "linux-image-generic not held — apt upgrade could break amdxdna later."
        warn "Run Section 02 to set the hold."
    else
        success "Kernel meta-packages held (linux-image-generic)"
    fi

    # CPU must be AMD
    if ! grep -q "AMD" /proc/cpuinfo; then
        warn "Non-AMD CPU detected — amdgpu / ROCm install may fail."
    fi

    # Existing AMD repo files: just inform; auto-repair runs as a separate step
    # (_xrt_repair_amd_repos) right after pre-checks return.
    if compgen -G '/etc/apt/sources.list.d/amdgpu*.list' >/dev/null \
       || compgen -G '/etc/apt/sources.list.d/rocm*.list' >/dev/null; then
        log "Existing amdgpu/rocm repo files detected — auto-repair will run next:"
        ls /etc/apt/sources.list.d/amdgpu*.list /etc/apt/sources.list.d/rocm*.list 2>/dev/null \
            | sed 's/^/    /' | tee -a "$LOG_FILE" >/dev/null
    fi

    [[ "$fatal" -eq 1 ]] && return 1
    return 0
}

# ----------------------------------------------------------------------------
# Auto-repair stale AMD repo source entries.
#
# Three classes of issue we fix (all caused by AMD's mid-2024 repo migration
# combined with strict APT signing in Ubuntu 24.04):
#   1. Stale URL versions — e.g. "amdgpu/7.2.2/ubuntu" returns 404 because AMD
#      moved amdgpu/ to "30.X.Y" versioning. Same for graphics/ where 7.2.2
#      was skipped.
#   2. Deprecated `proprietary` component — AMD removed it; everything is in
#      `main` now.
#   3. Missing `signed-by=` directive — APT in Ubuntu 24.04 hard-fails on
#      unsigned sources (was a warning before).
#
# Idempotent. Safe to run on clean systems (no-op).
# ----------------------------------------------------------------------------
_xrt_repair_amd_repos() {
    log "Auto-repair: scanning AMD repo source files for stale entries..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] would scan /etc/apt/sources.list.d/ and repair stale AMD URLs"
        return 0
    fi

    # Find all files referencing repo.radeon.com/amdgpu or graphics
    local repo_files=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && repo_files+=("$f")
    done < <(sudo grep -lE "repo\.radeon\.com/(amdgpu|graphics)" \
                /etc/apt/sources.list.d/*.list \
                /etc/apt/sources.list.d/*.sources 2>/dev/null || true)

    if [[ ${#repo_files[@]} -eq 0 ]]; then
        success "No pre-existing AMD repo files (clean state)"
        return 0
    fi

    log "Auto-repair: scanning ${#repo_files[@]} file(s)"

    local changes=0 needs_key=0
    local f
    for f in "${repo_files[@]}"; do
        local before after
        before=$(sudo cat "$f")
        after="$before"

        # 1. Stale amdgpu/X.Y.Z URLs (probe each unique URL with curl)
        local url
        for url in $(echo "$before" | grep -oE "https://repo\.radeon\.com/amdgpu/[0-9.]+/ubuntu" | sort -u); do
            if ! _xrt_url_works "${url}/dists/noble/InRelease"; then
                local latest
                latest=$(_xrt_get_latest_amd_version amdgpu)
                if [[ -n "$latest" ]]; then
                    local new_url="https://repo.radeon.com/amdgpu/${latest}/ubuntu"
                    log "  $f: stale URL $url → $new_url"
                    after=$(echo "$after" | sed "s|$url|$new_url|g")
                else
                    warn "  $f: $url is stale but couldn't determine latest amdgpu version"
                fi
            fi
        done

        # 2. Stale graphics/X.Y.Z URLs (same dance)
        for url in $(echo "$before" | grep -oE "https://repo\.radeon\.com/graphics/[0-9.]+/ubuntu" | sort -u); do
            if ! _xrt_url_works "${url}/dists/noble/InRelease"; then
                local latest
                latest=$(_xrt_get_latest_amd_version graphics)
                if [[ -n "$latest" ]]; then
                    local new_url="https://repo.radeon.com/graphics/${latest}/ubuntu"
                    log "  $f: stale URL $url → $new_url"
                    after=$(echo "$after" | sed "s|$url|$new_url|g")
                else
                    warn "  $f: $url is stale but couldn't determine latest graphics version"
                fi
            fi
        done

        # 3. Deprecated `proprietary` component → `main`
        if echo "$after" | grep -qE "^deb .*noble proprietary"; then
            log "  $f: component 'proprietary' deprecated → switching to 'main'"
            after=$(echo "$after" | sed -E 's|(^deb .*) noble proprietary|\1 noble main|g')
        fi

        # 4. Missing signed-by directive (APT 24.04 hard-fails)
        if echo "$after" | grep -qE "^deb https://repo\.radeon\.com/"; then
            log "  $f: missing [signed-by=...] → adding rocm.gpg directive"
            after=$(echo "$after" | sed -E 's|^deb https://repo\.radeon\.com|deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com|g')
            needs_key=1
        fi

        if [[ "$after" != "$before" ]]; then
            echo "$after" | sudo tee "$f" >/dev/null
            changes=$((changes + 1))
        fi
    done

    if [[ "$needs_key" == "1" ]]; then
        _xrt_ensure_rocm_key || {
            error "Could not set up rocm.gpg key — repaired sources will fail to verify"
            return 1
        }
    fi

    if [[ "$changes" -gt 0 ]]; then
        log "Auto-repair: modified $changes file(s). Refreshing apt cache..."
        sudo apt update >>"$LOG_FILE" 2>&1 || warn "apt update returned non-zero after repair"
        # Final check: any remaining hard errors on AMD sources?
        if sudo apt update 2>&1 | grep -qE "(repo\.radeon\.com).*\b(Err|404|NO_PUBKEY)\b"; then
            warn "AMD repos still report errors after repair — see: sudo apt update"
            return 1
        fi
        success "Auto-repair: AMD repo files fixed and apt cache refreshed"
    else
        success "Auto-repair: all AMD repo files already valid (no changes)"
    fi
    return 0
}

# Probe a URL via curl HEAD; return 0 if HTTP 200, 1 otherwise.
_xrt_url_works() {
    local url="$1"
    local code
    code=$(curl -fsSL -o /dev/null --max-time 10 -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    [[ "$code" == "200" ]]
}

# Discover the latest valid version directory under repo.radeon.com/<channel>/.
# Args: channel = "amdgpu" or "graphics"
# Output: "30.30.3" / "7.2.3" / "" if discovery fails.
_xrt_get_latest_amd_version() {
    local channel="$1"
    curl -fsSL --max-time 15 "https://repo.radeon.com/${channel}/" 2>/dev/null \
        | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+/"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -V \
        | tail -1
}

# Make sure /etc/apt/keyrings/rocm.gpg exists (download if missing). AMD signs
# all of rocm/, graphics/, and amdgpu/ with the same key — so this one keyring
# satisfies all repaired sources.
_xrt_ensure_rocm_key() {
    if [[ -f /etc/apt/keyrings/rocm.gpg ]]; then
        log "  rocm.gpg keyring already present"
        return 0
    fi
    log "  Downloading AMD GPG key → /etc/apt/keyrings/rocm.gpg"
    sudo install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL --max-time 15 https://repo.radeon.com/rocm/rocm.gpg.key \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg 2>/dev/null; then
        error "Failed to download/dearmor AMD GPG key from rocm.gpg.key"
        return 1
    fi
    sudo chmod a+r /etc/apt/keyrings/rocm.gpg
    success "  AMD GPG key installed"
    return 0
}

_xrt_locate_bundle() {
    log "Looking for XRT bundle at: $XRT_BUNDLE_DIR"

    if [[ ! -d "$XRT_BUNDLE_DIR" ]]; then
        ensure_dir "$XRT_BUNDLE_DIR"
        warn "Bundle directory created (was missing): $XRT_BUNDLE_DIR"
    fi

    # The 4 XRT .deb files are EULA-gated (must be downloaded manually from
    # AMD Ryzen AI Software portal). Validate their presence.
    local missing=()
    local bundle_files=(
        "xrt_*_24.04-amd64-base.deb"
        "xrt_*_24.04-amd64-base-dev.deb"
        "xrt_*_24.04-amd64-npu.deb"
        "xrt_plugin*amdxdna.deb"
    )
    for pattern in "${bundle_files[@]}"; do
        if ! compgen -G "$XRT_BUNDLE_DIR/$pattern" >/dev/null; then
            missing+=("$pattern")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "XRT bundle incomplete. Missing files matching:"
        for p in "${missing[@]}"; do
            error "  - $XRT_BUNDLE_DIR/$p"
        done
        cat >&2 <<'EOF'

The XRT files are EULA-gated and cannot be auto-downloaded. You need to:

  1. Visit: https://www.amd.com/en/developer/resources/ryzen-ai-software.html
  2. Sign in with AMD account, accept EULA
  3. Download Linux driver package (e.g. ryzen_ai-X.Y.Z.tgz)
  4. Extract:  tar -xzf ryzen_ai-X.Y.Z.tgz
  5. Locate the 4 .deb files inside the extracted folder
  6. Place them in: ~/Downloads/xrt-bundle/
     (or set XRT_BUNDLE_DIR=/your/path)

Once placed, re-run:  ./scripts/setup.sh --section 11a

For the alternative pure-FOSS route (build from amd/xdna-driver source),
see docs/09-xrt-stack.md.

EOF
        return 1
    fi

    success "XRT bundle found at $XRT_BUNDLE_DIR"
    log "Files detected:"
    for f in "$XRT_BUNDLE_DIR"/*.deb; do
        [[ -f "$f" ]] && log "  - $(basename "$f")"
    done
    return 0
}

_xrt_install_amdgpu_install() {
    # Look for amdgpu-install_*.deb in the bundle dir first
    local local_amdgpu
    local_amdgpu=$(compgen -G "$XRT_BUNDLE_DIR/amdgpu-install_*_all.deb" | head -1)

    if [[ -n "$local_amdgpu" ]]; then
        log "Using local amdgpu-install: $local_amdgpu"
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY-RUN] sudo apt install -y $local_amdgpu"
            return 0
        fi
        sudo apt install -y "$local_amdgpu" >>"$LOG_FILE" 2>&1 || {
            error "amdgpu-install .deb install failed"
            return 1
        }
        sudo apt update >>"$LOG_FILE" 2>&1 || true
        success "amdgpu-install (local) installed"
        return 0
    fi

    # Auto-download from repo.radeon.com (public URL, no EULA gate)
    log "amdgpu-install_*.deb not in bundle — auto-downloading from repo.radeon.com..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] curl + dpkg amdgpu-install latest from $AMDGPU_INSTALL_INDEX"
        return 0
    fi

    # Parse the index page to find latest amdgpu-install_*.deb filename
    local index_html
    index_html=$(curl -fsSL "$AMDGPU_INSTALL_INDEX" 2>/dev/null) || {
        error "Failed to fetch amdgpu-install index from $AMDGPU_INSTALL_INDEX"
        return 1
    }
    local filename
    filename=$(echo "$index_html" | grep -oE 'amdgpu-install_[0-9.+-]+_all\.deb' | head -1)
    if [[ -z "$filename" ]]; then
        error "Could not parse amdgpu-install filename from $AMDGPU_INSTALL_INDEX"
        error "Check the URL manually and place the .deb in $XRT_BUNDLE_DIR"
        return 1
    fi

    log "Downloading $filename..."
    local tmp_deb
    tmp_deb=$(mktemp --suffix=.deb)
    if ! curl -fsSL "${AMDGPU_INSTALL_INDEX}${filename}" -o "$tmp_deb"; then
        error "Download failed: ${AMDGPU_INSTALL_INDEX}${filename}"
        rm -f "$tmp_deb"
        return 1
    fi

    sudo apt install -y "$tmp_deb" >>"$LOG_FILE" 2>&1 || {
        error "amdgpu-install .deb install failed"
        rm -f "$tmp_deb"
        return 1
    }
    rm -f "$tmp_deb"
    sudo apt update >>"$LOG_FILE" 2>&1 || true
    success "amdgpu-install ($filename) installed from repo.radeon.com"
}

_xrt_run_amdgpu_install() {
    if ! command -v amdgpu-install &>/dev/null; then
        error "amdgpu-install command not found after install — abort"
        return 1
    fi

    # Idempotency-ish: skip if rocm-core already installed (proxy for "ROCm is set up")
    if dpkg -l rocm-core 2>/dev/null | grep -q "^ii"; then
        success "rocm-core already installed — skipping amdgpu-install run"
        return 0
    fi

    log "Running amdgpu-install --usecase=rocm,hiplibsdk --no-dkms (this can take 5-15 min)..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo amdgpu-install -y --accept-eula --usecase=rocm,hiplibsdk --no-dkms"
        return 0
    fi

    if sudo amdgpu-install -y --accept-eula \
        --usecase=rocm,hiplibsdk --no-dkms >>"$LOG_FILE" 2>&1; then
        success "amdgpu-install completed (ROCm + HIP SDK installed, kernel module skipped)"
    else
        error "amdgpu-install failed — see $LOG_FILE for full output"
        return 1
    fi
}

_xrt_add_user_groups() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] sudo usermod -aG render,video $USER"
        return 0
    fi

    local need_render=0 need_video=0
    if ! id -nG "$USER" | grep -qw render; then need_render=1; fi
    if ! id -nG "$USER" | grep -qw video;  then need_video=1;  fi

    if [[ "$need_render" -eq 0 ]] && [[ "$need_video" -eq 0 ]]; then
        success "$USER already in render + video groups"
        return 0
    fi

    sudo usermod -aG render,video "$USER" || {
        error "usermod failed"
        return 1
    }
    success "Added $USER to render + video groups"
    warn "Group changes only take effect after reboot/re-login"
}

# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] — 2026-05-10

### Fixed

- **Section 02 GRUB_DEFAULT failure on Ubuntu 24.04 with multiple kernels** — `_set_default_boot` in `scripts/lib/02-kernel-pin.sh` was returning silently with `GRUB_DEFAULT=0` (= boot the latest kernel = `-23`) when both the menuentry-id awk strategy and the position-based fallback failed. Reported by user with kernels `-20` and `-23` both installed and grub.cfg containing the entry at line 190 — but with function-defs noise at the top of grub.cfg breaking the menuentry-id parser.

  Fix introduces a new **Strategy A: title-based** that writes the human-readable form GRUB supports natively:
  ```
  GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-20-generic"
  ```
  Title-based runs first; existing menuentry-id and position-pair strategies are kept as fallbacks (B and C).

- **Section 02 now propagates GRUB-update failure to the caller.** `_set_default_boot` returns non-zero (instead of silently warning + return 0) when none of the three strategies produce a valid `GRUB_DEFAULT` containing the target kernel version. `run_section_02_kernel_pin` writes a state marker `~/.cache/zenbook-s16-setup/sec02-grub-fix-needed` on failure.

### Added

- **Stage A banner: `MANUAL GRUB FIX NEEDED` variant.** When the GRUB-fail marker is present, Stage A prints a third banner variant with a copy-pasteable `sudo sed` command to fix `GRUB_DEFAULT` by hand, plus a fallback instruction to pick the kernel from the GRUB boot menu manually. Detected via the marker file in `scripts/lib/stages.sh`.

- **Verification step** at the end of `_set_default_boot`: re-reads `/etc/default/grub` and grep-checks that `GRUB_DEFAULT` contains the `TARGET_KERNEL` string (`6.17.0-20`). If not, returns non-zero with a clear error pointing at expected vs actual values.

- **`docs/02-kernel-pinning.md` — new "Manual GRUB fix" section** with the exact diagnostic + fix commands (the same ones referenced by the new banner). Step 4 of the script-flow description is rewritten to document the three GRUB strategies (A: title-based, B: menuentry-id, C: position-pair).

## [0.3.0] — 2026-05-10

### Added

- **Three-stage installer (`--stage A|B|C`)** — opinionated bundle entry points aligned to natural reboot points. Each stage is a single command; no flag soup.
  - **Stage A** = sec 01–02 (preflight + kernel pin) → reboot.
  - **Stage B** = sec 03–09 + 11a (apt/apps/steam + XRT prep) → reboot.
  - **Stage C** = sec 11b + 12 + 10 (XRT install + mise default langs + validate gen).
- New file `scripts/lib/stages.sh` (~150 lines) implementing `_run_stage_A/B/C`.
- **ASCII banner system** (`print_banner` in `common.sh`) shown at end of each stage. Includes a figlet "MIXEDDRIVE LAB" header + box border (color via `COLOR_BLUE`, respects `NO_COLOR`). Banner content adapts to runtime conditions (e.g. "REBOOT NOW" vs "no reboot needed" depending on whether the new kernel is already booted).
- **Bootstrap of `curl + ca-certificates + gnupg`** at the top of `setup.sh` via new `bootstrap_minimal_deps` helper. Always runs (even in `--dry-run`), since these are dry-run prerequisites.
- **Stage A heads-up about XRT bundle** — printed in the post-stage-A banner so the user can download the EULA-gated AMD `.deb` files while the machine reboots.
- **Graceful skip of XRT prep (sec 11a) in Stage B** when the bundle is missing. Controlled by new env var `XRT_SKIP_IF_BUNDLE_MISSING=1` (set by Stage B/C runners; manual `--section 11a` still hard-fails as before).
- **Graceful skip of XRT install (sec 11b) in Stage C** when the prep marker is absent (i.e. user never ran 11a / has no bundle).
- **`ZENBOOK_SKIP_MISE_DEFAULTS=1`** env var to skip the long Erlang OTP build in Stage C while keeping the rest.
- `--help` added to `scripts/validate.sh`.

### Changed

- **`README.md` quick start** rewritten around the 3-stage flow. Old "All sections" table replaced with a 3-row stage table.
- **`scripts/setup.sh`** rewritten around `--stage` / `--section` argument parsing.
- **Mutual exclusion** between `--stage` and `--section`. Either is required (no implicit "default flow" — explicit only).
- Version badge bumped `v0.2.1` → `v0.3.0` in README. (Old badges were re-encoded camo URLs; switched back to direct shields.io URLs for easier updates.)

### Removed

- **BREAKING:** `--all` flag removed.
- **BREAKING:** `--with-ai-stack`, `--with-apps`, `--with-flatpak`, `--with-gaming`, `--with-xrt`, `--with-mise-defaults` flags all removed. Their functionality is now bundled into the 3 stages.
- The implicit "minimal install if no flags" default flow (sections 01–05) is gone — `setup.sh` now requires either `--stage` or `--section`.

### Fixed

- **`--dry-run` no longer fails on a fresh Ubuntu install** where `curl` is missing. Bootstrap installs `curl + ca-certificates + gnupg` for real (even in dry-run mode), since `curl` is needed by `gh_latest_tag`, the preflight internet check, and most repo helpers.
- **`gh_latest_tag`** now returns a placeholder `"0.0.0-dryrun"` when `DRY_RUN=true` instead of calling out to api.github.com. This unblocks `--dry-run --section 07` (LocalSend / LazyGit / LazyDocker installers) on systems with no network.
- **`scripts/lib/01-preflight.sh`** internet check now skipped under `--dry-run` (was emitting misleading "Cannot reach archive.ubuntu.com" when the real cause was missing `curl`).
- **`scripts/lib/07-apps-stack.sh`** — moved `[[ DRY_RUN == true ]] && return 0` above the `gh_latest_tag` call in `_install_localsend`, `_install_lazygit`, `_install_lazydocker`. Previously they would still hit the network in dry-run.

### Migration notes

If you have a script or doc that calls `./scripts/setup.sh --all` (or any `--with-*`), replace it with the relevant stage:

| Old | New |
|---|---|
| `./scripts/setup.sh` (no args) | `./scripts/setup.sh --stage A` then B, then C |
| `./scripts/setup.sh --all` | `--stage A` → reboot → `--stage B` → reboot → `--stage C` |
| `./scripts/setup.sh --with-xrt` | covered by Stage B (prep) + Stage C (install) |
| `./scripts/setup.sh --with-mise-defaults` | covered by Stage C (or `--section 12`) |
| `./scripts/setup.sh --dry-run --all` | `--dry-run --stage A` (or B / C) |

For granular re-runs, `--section NN` is unchanged.

## [0.2.2] — 2026-05-09

### Fixed

- **NPU PCI device ID detection in `zenbook-validate`** — corrected wrong device ID `1502` (typo, produced false miss `lspci: no signal processing device matching id 1502` despite NPU being present and functional). Replaced with multi-ID match against all known AMD Ryzen AI variants:
  - `1022:17f0` Strix Point / Krackan Point / Strix Halo (XDNA 2) — Zenbook S16 falls here
  - `1022:17f1` Strix Halo newer rev
  - `1022:1502` Phoenix (XDNA 1, older Ryzen 7040)
  - `1022:150e` Hawk Point (XDNA 1.5)
- 2-tier detection in `scripts/lib/10-validate.sh`:
  1. Primary: exact match against the 4 known IDs above. Output now reports the actual ID detected (e.g. `lspci: AMD NPU detected (1022:17f0)`).
  2. Fallback: generic "Signal processing" controller match for forward compat with future SKUs.
- `docs/02-kernel-pinning.md` "Verifying the NPU works" expected output updated from the bogus `signal processing device 1502 detected` to `AMD NPU detected (1022:17f0)`.

### Background

User report: after a successful XRT install, `zenbook-validate` showed `✗ lspci: no signal processing device matching id 1502` while all other amdxdna checks (lsmod, /dev/accel, dmesg) were green. Investigation showed `1502` was a typo from the v0.1.0 initial validation block — Phoenix-era device ID coincidentally exists, but Strix Point uses `17f0`. Manual confirmation: `lspci -nn` on the Zenbook S16 shows `Signal processing controller [1180]: ... [1022:17f0]`.

## [0.2.1] — 2026-05-09

### Added

- **`--with-mise-defaults`** flag (Section 12, opt-in) for bulk-installing 8 default language toolchains:
  - **mise-managed** (`mise use --global`):
    - Node.js (`lts`)
    - **Python: `3.12` (default), `3.13`, `latest` — three versions side-by-side.** Default `python` resolves to 3.12 for broad SLAM/CV ecosystem compat (OpenCV bindings, Open3D, ORB-SLAM3 wrappers stable on 3.12). Per-project override via `.mise.toml`.
    - Go (`latest`)
    - **Java: `21` (LTS default), `latest` — two versions side-by-side.** Default `java` resolves to 21 for broadest ecosystem support.
    - Ruby (`latest`) + `gem install rails --no-document` + `idiomatic_version_file_enable_tools` for `.ruby-version` detection
    - Erlang (`latest` — builds OTP from source, ~15-30 min on Zenbook S16)
    - Elixir (`latest`, depends on Erlang, Hex installed via `mix local.hex --force`)
  - **apt-managed**: PHP + extensions (`php-{curl,apcu,intl,mbstring,opcache,pgsql,mysql,sqlite3,redis,xml,zip}`) + Composer downloaded to `/usr/local/bin/composer`
  - **pip-managed (in mise's default Python)**: **`uv` (Astral)** — modern Python package + venv manager (`uv venv`, `uv pip`, `uv add`, `uv run`); replaces `python -m venv` + `pip` + `pip-tools` workflow, ~30x faster than pip for cold installs
  - **rustup-managed** (outside mise): Rust via canonical `rustup-init` from `sh.rustup.rs`
- New section `12` (`scripts/lib/12-mise-defaults.sh`, ~330 lines).
- `--with-mise-defaults` flag and section `12` added to `setup.sh` argument parser, `_section_num`, single-section dispatch, and default flow execution.
- Erlang build dependencies pre-installed via apt before triggering the OTP build (`autoconf m4 libncurses-dev libwxgtk3.2-dev libwxgtk-webview3.2-dev libgl1-mesa-dev libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils`).
- `zenbook-validate` expanded:
  - Languages section adds checks for `elixir`, `erl` (Erlang), `rustup`, `composer`, `rails`, `uv`
  - New "mise default languages" block: queries `mise ls` and reports per-language status (node, python, go, java, ruby, erlang, elixir)

### Documentation

- `docs/04-dev-toolchain.md` — "Adding languages" rewritten to document both paths (manual `mise use` vs Section 12 bulk), with full caveats table per language. New "Python multi-version workflow + `uv`" section showing how to switch between 3.12/3.13/latest per project via `.mise.toml`, plus `uv` workflow examples (`uv venv`, `uv add`, `uv sync`, `uv run`).
- `README.md` — compatibility table includes `--with-mise-defaults` row, section IDs reference includes `12`.

### Notes

- `--all` shortcut intentionally does **not** include `--with-mise-defaults`. Reasons: 15-30 min Erlang OTP build + heavy Rails dep tree + ~600 MB extra disk for 3 Python versions.
- Section 12 is **idempotent**: re-runs check `mise ls` per language and skip already-installed tools. Same for `rustup` (re-running `-y` updates), apt-installed PHP, and `uv` (pip detects existing install).
- Rust install via rustup lives outside mise's PATH ordering — cargo/rustc resolved from `~/.cargo/bin/` (rustup adds it to `~/.bashrc` and `~/.profile`).
- `uv` installed via `mise x python -- python -m pip install --user uv` lands in `~/.local/bin/uv` (Ubuntu adds this to `$PATH` via `~/.profile`). Open a fresh terminal after Section 12 for `uv` to be visible.

## [0.2.0] — 2026-05-09

### Added

- **AMD XRT NPU stack** (`--with-xrt`, opt-in). Two-phase install with reboot in between:
  - **Section 11a** (`scripts/lib/11a-xrt-prep.sh`): pre-flight checks, locate XRT bundle (default `~/Downloads/xrt-bundle/`), auto-download `amdgpu-install_*.deb` from `repo.radeon.com` if missing, run `amdgpu-install --usecase=rocm,hiplibsdk --no-dkms`, add user to `render`+`video` groups, print "REBOOT REQUIRED" banner. State tracked at `~/.cache/zenbook-s16-setup/xrt-prep-done`.
  - **Section 11b** (`scripts/lib/11b-xrt-install.sh`): post-reboot install of the four XRT `.deb` files (base, base-dev, npu, plugin-amdxdna), append `source /opt/xilinx/xrt/setup.sh` to `~/.bashrc`, write `/etc/security/limits.d/99-amdxdna.conf` for memlock unlimited, run `xrt-smi examine` for verification.
  - **Smart dispatch**: `./scripts/setup.sh --with-xrt` runs 11a if not done, 11b if 11a is complete (detected via state file).
  - **EULA-gated files**: the four XRT `.deb` files are part of the AMD Ryzen AI Software bundle and require manual download (AMD account + EULA acceptance). `amdgpu-install_*.deb` is fetched from `repo.radeon.com/amdgpu-install/latest/ubuntu/noble/` (public).
  - **Bundle override**: `--xrt-bundle-dir <path>` flag or `XRT_BUNDLE_DIR` env var.

- New flag `--with-xrt` and `--xrt-bundle-dir <path>` for `setup.sh`.
- New section IDs `11a` and `11b` for `--section` dispatch.
- New documentation `docs/09-xrt-stack.md` covering manual download steps, two-phase flow, manual verification commands, troubleshooting (`SVA bind device failed`, `xrt-smi` no devices, DKMS build failures, missing kernel headers), removal procedure, and an alternative build-from-source path via `amd/xdna-driver`.
- `zenbook-validate` now checks for `xrt-smi`, ROCm, `render`/`video` group membership, memlock limits, and runs `xrt-smi examine` to detect NPU device.

### Changed

- README.md compatibility table includes `--with-xrt` row.
- README.md docs list includes `docs/09-xrt-stack.md`.
- Section IDs reference updated to include `11a` and `11b`.
- `--all` shortcut intentionally does **not** include `--with-xrt` — XRT requires manual file provisioning, so it stays opt-in.

### Notes

- XRT install requires kernel `6.17.0-20-generic` booted (Section 02 must run first).
- `--no-dkms` flag on `amdgpu-install` is critical: it preserves the held HWE kernel's `amdxdna` module rather than letting `amdgpu-install` ship its own.
- The DKMS module from `xrt_plugin*amdxdna.deb` builds against `linux-headers-6.17.0-20-generic`; the `linux-headers-generic-hwe-24.04` package (installed in Section 04) is held alongside the kernel.

## [0.1.2] — 2026-05-09

### Fixed

- **Kernel pin GRUB default — `saved` strategy abandoned.** v0.1.1's `GRUB_DEFAULT=saved` + `grub-set-default` approach proved fragile in practice (relies on writeable `/boot/grub/grubenv`, can be silently overwritten by `update-grub`, hard to verify post-set). Replaced with **static `GRUB_DEFAULT="<menuentry-id>"`** approach.

  New strategy in `scripts/lib/02-kernel-pin.sh::_set_default_boot`:

  1. **Primary**: parse `/boot/grub/grub.cfg` for the menuentry id of `6.17.0-20-generic` (e.g. `gnulinux-6.17.0-20-generic-advanced-UUID`) — position-independent, survives kernel add/remove.
  2. **Fallback**: position-pair like `"1>2"` (Submenu>Entry index) — what works for the typical Ubuntu 24.04 kernel-pinning setup.
  3. **Verification**: re-run `update-grub` after writing `GRUB_DEFAULT`, then read back and log final config.

- **Validation script** updated to recognize three valid `GRUB_DEFAULT` formats (menuentry-id, position-pair, or kernel name) and cross-check against `uname -r`. Old `GRUB_DEFAULT=saved` is now flagged as a known-fragile config from v0.1.1.

### Background

User report: setup ran successfully, kernel `6.17.0-20-generic` was installed and held, but `uname -r` after reboot consistently returned `6.17.0-23-generic` because GRUB defaulted to position 0 (the latest kernel). User fix: `sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="1>2"/' /etc/default/grub && sudo update-grub`. v0.1.2 implements this pattern with menuentry-id resolution as the more robust primary path.

## [0.1.1] — 2026-05-09

### Fixed

- **Cursor install** — Replaced deprecated AppImage download URL (`download.cursor.sh/linux/appImage/x64`) with Cursor's official APT repository at `downloads.cursor.com/aptrepo`. AppImage handling, `~/Applications/Cursor.AppImage` path, and the manual `.desktop` entry generation are removed in favor of `apt install cursor`.
- **Steam install** — Section 09 now enables `i386` architecture (`dpkg --add-architecture i386`) before `apt install steam-installer`. Steam's 32-bit dependency (`steam-libs-i386`) was not installable without it. Multiverse repo enable + `apt update` ordering fixed so package lists pick up i386 packages before install.
- **Flatpak detection (false negative)** — `flatpak_check` and `flatpak_install` previously parsed `flatpak list --app` with `awk '{print $2}'`, which broke when app names contained spaces (e.g. "OnlyOffice Desktop") or when locale changed column alignment. Replaced with `flatpak list --app --columns=application` for explicit App ID column.
- **Kernel pin GRUB default** — Section 02's `_set_default_boot` now actually configures GRUB to remember the last-booted kernel (`GRUB_DEFAULT=saved` + `GRUB_SAVEDEFAULT=true`) and runs `grub-set-default` against the parsed `6.17.0-20-generic` menuentry. Previously it only ran `update-grub`, which made the kernel *bootable* but not *default* — users had to pick it from the GRUB menu manually.

### Added

- Validation script now checks:
  - i386 architecture status (warns if Steam would fail)
  - Currently-booted kernel matches `6.17.0-20-generic` (warns if booted on `-23+`)
  - `GRUB_DEFAULT=saved` config (warns if a future kernel install could shift default boot)

### Changed

- `docs/05-apps-catalog.md` — Updated Cursor sign-in command (`cursor` instead of `~/Applications/Cursor.AppImage`) and removal instructions (`sudo apt remove cursor`).
- `docs/08-troubleshooting.md` — Cursor troubleshooting rewritten for apt-installed binary (no more AppImage / libfuse2 specifics).

## [0.1.0] — 2026-05-09

### Added

- Initial public release.
- Modular setup script with 10 sections under `scripts/lib/`.
- Section 01 — Pre-flight checks (Ubuntu 24.04, amd64, sudo, internet, hardware ID).
- Section 02 — Kernel pin to `6.17.0-20-generic` for `amdxdna` NPU compatibility, with `apt-mark hold` on kernel meta-packages.
- Section 03 — Base APT packages (build essentials, terminal QoL, GitHub CLI, Flatpak runtime, common CLI utilities).
- Section 04 — Extended APT (runtime libs for Ruby/Python/Postgres, Vulkan/Mesa GPU stack, `thermald`, `lm-sensors`, `stress-ng`, `gfortran`, basic SLAM dev libs).
- Section 05 — Dev toolchain: `mise` version manager + Docker CE + Compose v2.
- Section 06 — AI stack (`--with-ai-stack`): Cursor, Warp Terminal, Node.js 22 LTS, Claude Code CLI.
- Section 07 — Apps stack (`--with-apps`): 1Password, Google Chrome, LocalSend, Typora, Gum, LazyGit, LazyDocker, Ulauncher.
- Section 08 — Flatpak apps (`--with-flatpak`): OnlyOffice, Obsidian, Audacity, GIMP, Pinta, VLC, HandBrake, Kdenlive, Spotify, Discord, Zoom.
- Section 09 — Gaming (`--with-gaming`): Steam + ProtonUp-Qt.
- Section 10 — Validation script generated at `~/.local/bin/zenbook-validate` (always runs via EXIT trap).
- `--dry-run` flag for previewing without changes.
- `--all` shortcut to enable all opt-in sections.
- `--section N` flag to run a single section.
- Documentation under `docs/`: pre-install, kernel pinning rationale, package catalog, dev toolchain, apps catalog, Flatpak rationale, post-install validation, troubleshooting, hardware quirks.
- GitHub Actions workflow running `shellcheck` on every push.
- Issue templates for bug reports and hardware compatibility reports.

# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

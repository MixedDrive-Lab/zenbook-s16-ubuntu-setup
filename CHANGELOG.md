# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

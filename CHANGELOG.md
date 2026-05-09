# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

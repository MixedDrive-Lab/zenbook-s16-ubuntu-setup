# zenbook-s16-ubuntu-setup

> Battle-tested Ubuntu 24.04 LTS setup for ASUS Zenbook S16 (UM5606) with AMD Ryzen AI 9 HX 370. Kernel 6.17.0-20 pinned for amdxdna NPU compatibility. Auto-setup script + manual walkthrough.

[![License: MIT](https://camo.githubusercontent.com/fdf2982b9f5d7489dcf44570e714e3a15fce6253e0cc6b5aa61a075aac2ff71b/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f4c6963656e73652d4d49542d79656c6c6f772e737667)](https://opensource.org/licenses/MIT) [![Ubuntu](https://camo.githubusercontent.com/b93b8202d2b5859f39a6f71b5f3d130488d6ab260b606cf5c59e7c5facb177b9/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f5562756e74752d32342e30342532304c54532d4539353432303f6c6f676f3d7562756e7475266c6f676f436f6c6f723d7768697465)](https://releases.ubuntu.com/24.04/) [![Hardware](https://camo.githubusercontent.com/ce280271e2b052df21b6f5536254a60d1a3d5fbd55ae926a1a8180ebd75d5468/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f48617264776172652d5a656e626f6f6b2532305331362d626c7565)](https://github.com/MixedDrive-Lab/zenbook-s16-ubuntu-setup/blob/v0.1.2)

------

## What This Is

This repository contains the development environment setup used at [MixedDrive Lab](https://mixeddrivelab.org/) on the primary research workstation: **ASUS Zenbook S16 (UM5606)** with **AMD Ryzen AI 9 HX 370** and **32 GB RAM**, running **Ubuntu 24.04.4 LTS** (Wayland).

> **Status:** alpha (`v0.2.1`). Tested on a single Zenbook S16 UM5606HA. PRs welcome — see `.github/ISSUE_TEMPLATE/hardware_compat.md` if you have a different revision.

## What this gives you

| Layer | Default | Description |
|---|:-:|---|
| Pre-flight checks | ✅ | Verifies Ubuntu 24.04, amd64, sudo, internet, disk space, hardware ID |
| Kernel pin (`6.17.0-20`) | ✅ | Avoids the `amdxdna_drm_open: SVA bind device failed, ret -95` regression on kernels ≥ 6.17.0-22 |
| Base APT packages | ✅ | `build-essential`, common dev libs, terminal QoL (`ripgrep`, `eza`, `zoxide`, `fzf`, `bat`, `fd-find`, etc), GitHub CLI, Flatpak runtime |
| Extended APT | ✅ | Runtime libs (Ruby/Python/Postgres deps), full Vulkan/Mesa stack (Steam-ready), `thermald`, `lm-sensors`, `stress-ng`, `gfortran`, SLAM dev libs (`libeigen3-dev`, `libopencv-dev`, `libceres-dev`) |
| Dev toolchain | ✅ | [`mise`](https://mise.jdx.dev) version manager, Docker CE + Compose v2 |
| AI stack | `--with-ai-stack` | Cursor, Warp Terminal, Node.js 22, Claude Code CLI |
| Apps stack | `--with-apps` | 1Password, Google Chrome, LocalSend, Typora, Gum, LazyGit, LazyDocker, Ulauncher |
| Flatpak apps | `--with-flatpak` | OnlyOffice, Obsidian, Audacity, GIMP, Pinta, VLC, HandBrake, Kdenlive, Spotify, Discord, Zoom |
| Gaming | `--with-gaming` | Steam + ProtonUp-Qt |
| AMD XRT NPU stack | `--with-xrt` | ROCm + XRT runtime + XDNA plugin (two-phase install with reboot in between, requires user-provided EULA-gated .deb files — see [`docs/09-xrt-stack.md`](docs/09-xrt-stack.md)) |
| mise default languages | `--with-mise-defaults` | Bulk-install 8 languages: Python/Node/Go/Java/Ruby (+Rails)/Erlang/Elixir via mise; PHP via apt + Composer; Rust via rustup. Erlang OTP build ~15-30 min. See [`docs/04-dev-toolchain.md`](docs/04-dev-toolchain.md) for caveats. |

All sections are **idempotent** — re-running is safe.

## Quick start

```bash
# 1. Clone
git clone https://github.com/MixedDrive-Lab/zenbook-s16-ubuntu-setup.git
cd zenbook-s16-ubuntu-setup

# 2. Preview what will happen (no changes made)
./scripts/setup.sh --dry-run --all

# 3. Minimal install (sections 01–05: kernel + base + dev toolchain only)
./scripts/setup.sh

# 4. Or full install
./scripts/setup.sh --all

# 5. Reboot to switch to kernel 6.17.0-20-generic
sudo reboot

# 6. Verify post-reboot
zenbook-validate
```

A timestamped log lands at `~/.cache/zenbook-s16-setup/setup-YYYYMMDD-HHMMSS.log`.

## Why kernel `6.17.0-20`?

Kernels `≥ 6.17.0-22` shipped in Ubuntu's HWE channel introduced a regression that breaks the **`amdxdna`** driver — the NPU on AMD Ryzen AI / Strix Point silicon — surfacing as:

```
amdxdna_drm_open: SVA bind device failed, ret -95
```

Root cause: commit *"iommu: disable SVA when CONFIG_X86 is set"*. Last known good build is **`6.17.0-20-generic`**. Section 02 of the setup installs that exact build and runs `apt-mark hold` on the kernel meta-packages so a routine `apt upgrade` won't silently break the NPU again. Skip it with `ZENBOOK_SKIP_KERNEL_PIN=1` if you don't need NPU access.

Once upstream lands a fix, drop the hold:

```bash
sudo apt-mark unhold linux-image-generic linux-headers-generic linux-generic
```

See [`docs/02-kernel-pinning.md`](docs/02-kernel-pinning.md) for the full story + manual fallback steps if `6.17.0-20` is no longer in the apt archive.

## Running specific sections

```bash
# Just the kernel pin
./scripts/setup.sh --section 02

# Just the dev toolchain (mise + Docker)
./scripts/setup.sh --section 05

# Just regenerate the validation script
./scripts/validate.sh
```

Section IDs: `01` preflight, `02` kernel pin, `03` apt base, `04` apt extended, `05` dev toolchain, `06` ai stack, `07` apps, `08` flatpak, `09` gaming, `10` validation, `11a` xrt prep, `11b` xrt install, `12` mise default languages.

## Repository layout

```
zenbook-s16-ubuntu-setup/
├── README.md                  # this file
├── CHANGELOG.md
├── LICENSE                    # MIT
├── docs/
│   ├── 01-pre-install.md      # USB bootable + Ubuntu install hints
│   ├── 02-kernel-pinning.md   # amdxdna bug deep dive
│   ├── 03-apt-packages.md     # what each package is for
│   ├── 04-dev-toolchain.md    # mise + Docker usage
│   ├── 05-apps-catalog.md     # rationale for each opt-in app
│   ├── 06-flatpak-apps.md     # Flatpak vs apt
│   ├── 07-validation.md       # post-install checks
│   ├── 08-troubleshooting.md  # common issues
│   ├── 09-xrt-stack.md        # AMD XRT NPU stack (--with-xrt)
│   └── hardware-quirks.md     # Zenbook S16 specifics (battery, webcam, etc)
├── scripts/
│   ├── setup.sh               # main entry — see ./scripts/setup.sh --help
│   ├── validate.sh            # standalone validation
│   └── lib/                   # one file per section
└── .github/
    ├── ISSUE_TEMPLATE/
    └── workflows/
        └── shellcheck.yml     # CI lint
```

## Compatibility

- ✅ ASUS Zenbook S16 UM5606HA (AMD Ryzen AI 9 HX 370, Radeon 890M, NPU)
- ⚠️ Other AMD Ryzen AI / Strix Point laptops: kernel pin should still apply; APT/Flatpak sections are vendor-agnostic.
- ⚠️ Intel laptops: kernel pin is irrelevant. The rest mostly works but is untested.
- ❌ Non-Ubuntu distros: not supported. Pre-flight will warn.

## Contributing

Bug reports for different Zenbook revisions are very welcome — please use the **Hardware compatibility report** issue template. PRs to add new opt-in sections (e.g. `--with-rust-embedded`, `--with-data-science`) are also welcome; keep them behind a flag and update the README table.

Run `shellcheck` locally before opening a PR:

```bash
shellcheck scripts/setup.sh scripts/lib/*.sh scripts/validate.sh
```

CI runs the same on every push.

## License

[MIT](LICENSE) © MixedDrive Lab.

## Credits

- Skeleton informed by community knowledge around `amdxdna` regressions (LKML threads, Ubuntu kernel team mailing list).
- `mise`, LazyGit, LazyDocker, Gum, LocalSend — open-source projects this script wraps. Please star their repos.
- Built and tested at **MixedDrive Lab**, an independent research initiative based in Bandung, Indonesia.

# zenbook-s16-ubuntu-setup

> Battle-tested Ubuntu 24.04 LTS setup for ASUS Zenbook S16 (UM5606) with AMD Ryzen AI 9 HX 370. Kernel 6.17.0-20 pinned for amdxdna NPU compatibility. Auto-setup script + manual walkthrough.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/24.04/) [![Hardware](https://img.shields.io/badge/Hardware-Zenbook%20S16-blue)](https://github.com/MixedDrive-Lab/zenbook-s16-ubuntu-setup) [![Version](https://img.shields.io/badge/version-v0.3.3-brightgreen)](https://github.com/MixedDrive-Lab/zenbook-s16-ubuntu-setup/releases)

------

## What This Is

This repository contains the development environment setup used at [MixedDrive Lab](https://mixeddrivelab.org/) on the primary research workstation: **ASUS Zenbook S16 (UM5606)** with **AMD Ryzen AI 9 HX 370** and **32 GB RAM**, running **Ubuntu 24.04.4 LTS** (Wayland).

> **Status:** alpha (`v0.3.3`). Tested on a single Zenbook S16 UM5606HA. PRs welcome — see `.github/ISSUE_TEMPLATE/hardware_compat.md` if you have a different revision.

## What this gives you

A **three-stage installer** with reboots aligned to natural hardware events. Each stage is a single command — no flag soup. All sections are **idempotent**, so re-running any stage is safe.

| Stage | Sections | What you get | Followed by |
|:-:|---|---|---|
| **A** | 01 preflight, 02 kernel-pin | Verifies the system, installs + holds kernel `6.17.0-20-generic` (NPU compat) | 🔄 Reboot to activate kernel |
| **B** | 03–09 + 11a | All APT packages (base + dev libs + Vulkan/Mesa + Ruby/Python deps), `mise` + Docker, AI stack (Cursor/Warp/Node 22/Claude Code), apps (1Password/Chrome/LocalSend/Typora/LazyGit/LazyDocker/etc), Flatpak apps (Obsidian/VLC/Spotify/Discord/etc), Steam + ProtonUp-Qt, **and** AMD XRT NPU prep (ROCm + render/video groups) | 🔄 Reboot to activate group membership |
| **C** | 11b + 12 + 10 | XRT NPU runtime + 4 EULA-gated `.deb` files installed, 8 default languages via mise (Python/Node/Go/Java/Ruby+Rails/Erlang/Elixir/PHP/Rust — note: Erlang OTP build ~15–30 min), and `zenbook-validate` script generated | ✅ Run `zenbook-validate` |

**XRT NPU bundle** (Stage B / C): the 4 XRT `.deb` files are EULA-gated and cannot be auto-downloaded. Stage A prints a heads-up so you can fetch them from [AMD Ryzen AI Software](https://www.amd.com/en/developer/resources/ryzen-ai-software.html) while the machine reboots. If the bundle is missing when Stage B runs, sec 11a is silently skipped (re-run with `--section 11a` once the bundle is in place). See [`docs/09-xrt-stack.md`](docs/09-xrt-stack.md).

## Quick start

```bash
# 1. Clone
git clone https://github.com/MixedDrive-Lab/zenbook-s16-ubuntu-setup.git
cd zenbook-s16-ubuntu-setup

# 2. (Optional) Preview Stage B without changes
./scripts/setup.sh --dry-run --stage B

# 3. Stage A — preflight + kernel pin
./scripts/setup.sh --stage A
sudo reboot

# 4. Stage B — apt + apps + steam + XRT prep
./scripts/setup.sh --stage B
sudo reboot

# 5. Stage C — XRT install + mise default languages + validate gen
./scripts/setup.sh --stage C

# 6. Verify
zenbook-validate
```

**Skip the long Erlang OTP build** in Stage C:
```bash
ZENBOOK_SKIP_MISE_DEFAULTS=1 ./scripts/setup.sh --stage C
```

A timestamped log lands at `~/.cache/zenbook-s16-setup/setup-YYYYMMDD-HHMMSS.log`.

For all options:
```bash
./scripts/setup.sh --help
```

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

## Running a single section (escape hatch)

For re-runs after a fix, or to install just one thing:

```bash
# Just the kernel pin
./scripts/setup.sh --section 02

# Just the dev toolchain (mise + Docker)
./scripts/setup.sh --section 05

# Just XRT prep — e.g. after you finally got the EULA-gated bundle
./scripts/setup.sh --section 11a

# Just regenerate the validation script
./scripts/validate.sh
```

Section IDs: `01` preflight · `02` kernel pin · `03` apt base · `04` apt extended · `05` dev toolchain · `06` ai stack · `07` apps · `08` flatpak · `09` gaming · `10` validation · `11a` xrt prep · `11b` xrt install · `12` mise default languages.

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

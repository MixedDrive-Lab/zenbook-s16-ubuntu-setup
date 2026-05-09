# 03 — APT packages: what each layer is for

The script splits APT installs into two sections so you can opt out of one without losing the other.

## Section 03 — Base (`run_section_03_apt_base`)

The "every workstation needs this" set. ~150 MB after deduplication.

| Group | Packages | Why |
|---|---|---|
| Build | `build-essential cmake pkg-config autoconf bison clang gfortran` | Compile from source |
| Version control | `git` | Obvious |
| Common dev | `python3-pip python3-venv python3-dev pipx` | System Python tooling. (Per-project Python via `mise`, see Section 05.) |
| Archive | `unzip zip p7zip-full` | Decompress everything |
| TLS / signing | `ca-certificates gnupg gpg curl wget` | Required by half the third-party repos |
| Terminal QoL | `htop btop tmux tree ncdu ripgrep fd-find bat jq direnv fzf zsh` | Productivity multipliers |
| Modern CLI | `eza zoxide plocate apache2-utils tldr` | `eza` = better `ls`, `zoxide` = `cd` with frecency, `plocate` = fast file find, `tldr` = simplified man pages |
| Flatpak runtime | `flatpak gnome-software-plugin-flatpak gnome-shell-extension-manager` | Section 08 needs this |
| GitHub | `gh` (from `cli.github.com` repo) | `gh auth login`, `gh pr`, etc |
| Multimedia | `ffmpeg libimage-exiftool-perl rclone restic yamllint okular inkscape` | Common utilities — `restic` and `rclone` here so they're available even if you skip Section 08 |

## Section 04 — Extended (`run_section_04_apt_extended`)

The "you'll need these the moment you build something real" set. ~600 MB.

### Runtime libraries

| Packages | What needs them |
|---|---|
| `libssl-dev libreadline-dev zlib1g-dev libyaml-dev libncurses5-dev libffi-dev libgdbm-dev libjemalloc2` | Building Ruby, Python C-extensions, native gems |
| `libvips imagemagick libmagickwand-dev` | Image processing pipelines |
| `mupdf mupdf-tools` | PDF text extraction without GUI |
| `redis-tools sqlite3 libsqlite3-0` | Local data stores |
| `libmysqlclient-dev libpq-dev postgresql-client postgresql-client-common` | DB client libs (Postgres + MySQL) |

### SLAM / robotics

| Packages | Why |
|---|---|
| `libeigen3-dev` | Linear algebra header library — used by every SLAM code base |
| `libopencv-dev` | OpenCV 4.x system build |
| `libceres-dev` | Non-linear least squares — bundle adjustment, calibration |
| `libgtest-dev` | GoogleTest, used by the above for unit tests |

If you're not doing robotics work this is ~200 MB you don't strictly need — feel free to fork and remove.

### Vulkan / Mesa stack

This is the big one for an AMD Ryzen AI laptop. Steam, Proton, GPU compute, hardware video acceleration in Kdenlive/HandBrake — all of it depends on having a complete Mesa stack:

| Packages | Role |
|---|---|
| `vulkan-tools clinfo mesa-utils` | `vulkaninfo`, `clinfo`, `glxinfo` for diagnostics |
| `mesa-vulkan-drivers libvulkan1 vulkan-validationlayers` | Vulkan driver for AMD + validation layers for development |
| `libegl1-mesa-dev libgles2-mesa-dev libgl1-mesa-dri libglx-mesa0` | EGL / GLES / GLX (needed by Wayland clients and many GUI apps) |
| `mesa-va-drivers mesa-vdpau-drivers libva* vainfo` | VA-API for hardware video decode (Kdenlive playback, web video) |
| `libdrm-amdgpu1` | Direct Rendering Manager for amdgpu |
| `intel-media-va-driver-non-free` | Doesn't apply to Zenbook S16 but harmless — keeps the script useful for Intel laptops too |

After install, `vulkaninfo --summary` should list `AMD Radeon Graphics (RADV STRIX)` or similar.

### Kernel tools / monitoring

| Packages | Role |
|---|---|
| `linux-tools-generic linux-tools-common linux-headers-generic-hwe-24.04` | `perf`, `bpftool`, headers for out-of-tree modules |
| `thermald` | Intel thermal daemon — also active on AMD systems for general thermal tuning |
| `lm-sensors` | `sensors` command, plus the `sensors-detect` runtime (script runs it once non-interactively) |
| `stress-ng` | Synthetic load generator — handy for thermal validation |

### `fastfetch`

System info display, neofetch successor. Installed from PPA `ppa:zhangsongcui3371/fastfetch` for a recent build.

## Removing packages later

Everything in this section is installed via `apt`, so:

```bash
sudo apt remove <package>
sudo apt autoremove   # cleans up orphaned deps
```

The repos themselves persist in `/etc/apt/sources.list.d/`. If you want a clean state:

```bash
sudo rm /etc/apt/sources.list.d/{github-cli,docker,mise,typora}.list
sudo rm /etc/apt/keyrings/{docker.asc,mise-archive-keyring.gpg,typora.gpg}
sudo apt update
```

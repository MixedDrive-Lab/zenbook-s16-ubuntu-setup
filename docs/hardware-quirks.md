# Hardware quirks — ASUS Zenbook S16 (UM5606)

A running list of the laptop's hardware-specific behavior on Linux. Most can't be "fixed" by software — knowing about them up front saves frustration.

## Tested configuration

| Component | Detail |
|---|---|
| Model | ASUS Zenbook S16 UM5606 (HA / KA / WA variants) |
| CPU | AMD Ryzen AI 9 HX 370 (Strix Point, Zen 5 + Zen 5c, 12C/24T) |
| GPU | Radeon 890M (RDNA 3.5, 16 CU) |
| NPU | XDNA 2 (50 TOPS) |
| RAM | 32 GB LPDDR5X-7500 (soldered) |
| Display | 16" 3K (2880×1800) OLED 120Hz, ASUS Lumina, ~600 nits |
| Charger | 65 W USB-C PD |

If your variant differs (HX 365 / 32 GB vs 24 GB / non-OLED panel), please file a hardware compatibility issue.

## Confirmed working

| Feature | Notes |
|---|---|
| Wi-Fi 7 (MediaTek MT7925) | Works out of the box on kernel 6.17.x |
| Bluetooth 5.4 | Works |
| Webcam (RGB + IR) | RGB works in any V4L2 app. IR works for Windows Hello equivalents (`howdy`); not many tools use it on Linux |
| Fingerprint reader | Goodix-based, works with `fprintd` |
| Touchpad | Excellent under libinput. Two-finger scroll, three-finger gestures, palm rejection all work |
| OLED 120Hz at native res | Wayland session required for proper hi-DPI; fractional scaling works |
| GPU (Radeon 890M) | Mesa drivers, Vulkan, OpenGL all good |
| NPU (XDNA 2) | Works on `6.17.0-20`. Broken on `≥ 6.17.0-22` (see `02-kernel-pinning.md`) |
| Hardware video decode | VA-API works for H.264, H.265, AV1 |
| Speakers | Functional but not great |
| HDMI / USB-C DisplayPort | Both work, can drive 4K external |
| Suspend (s2idle) | Works on kernel 6.17.0-20 |

## Known limitations

### Battery drain in suspend (s2idle)

Modern AMD laptops use s2idle ("modern standby") rather than S3 deep sleep. Idle power is higher than older S3 designs. Expect ~5–15 % battery loss per 8 h of suspend. Workarounds:

- Hibernate (`systemctl hibernate`) for trips longer than a few hours — needs a swap partition ≥ RAM size
- Force `mem_sleep_default=deep` via GRUB kernel parameter (some firmware revisions reject this)
- Just live with it and plug in overnight

### Charger wattage during gaming

The 65 W charger isn't enough to fully sustain CPU+GPU peak draw. During heavy gaming you'll see slow battery drain even while plugged in. For sustained heavy load, consider a 100 W USB-C PD charger. The motherboard accepts up to 100 W per the USB-C PD spec.

### Webcam quality

Median for this price tier — washed-out colors under tungsten, noisy in low light. Hardware limitation, no software fix.

### Speaker quality

Two bottom-firing drivers, no proper tweeters. Fine for video calls and YouTube, painful for music. Use headphones or a USB DAC.

### Fan curve under sustained load

Default fan curve is conservative (quiet bias). Under heavy compile or training jobs, the SoC can throttle before the fans ramp up. Options:

- BIOS: switch to "Performance" mode
- `asusctl` (AUR-style) — limited support on Ubuntu, but usable: https://asus-linux.org
- Manual `thermald` profile tweaks (advanced, your call)

The script installs `thermald` so the daemon at least manages thermal limits proactively.

### Hibernate with LUKS

If you encrypted `/` with LUKS during install, hibernate writes the unencrypted RAM contents to swap. You **must** also encrypt swap — usually a `cryptswap` line in `/etc/crypttab` derived from your root key. Out of scope; see Ubuntu's encrypted-swap guide.

### MyASUS app for firmware updates

`fwupd` (`fwupdmgr update`) handles BIOS for some ASUS models, but the Zenbook S16's UEFI capsule isn't always published to LVFS. Workarounds:

- Boot back into Windows briefly to run MyASUS BIOS update
- ASUS publishes raw `.cap` files on the support page; `flashrom` is **not** safe on this hardware

## Watching for upstream improvements

| Area | Status (2026) | Watch |
|---|---|---|
| `amdxdna` SVA fix | Pending. Tracked in Linux IOMMU mailing list. | LKML thread "iommu: enable SVA on x86 with Strix Point" |
| Wayland HDR for OLED | GNOME 47+ has experimental support; not enabled by default | `gnome-shell --no-X11 --hdr-experimental` |
| ROCm support for Radeon 890M (RDNA 3.5 / gfx1150) | **Works with ROCm 7.2.3** — `rocminfo` reports `gfx1150` GPU agent, `xrt-smi validate` passes all tests. Requires correct `LD_LIBRARY_PATH` ordering (see `docs/09-xrt-stack.md` troubleshooting). | Confirmed on UM5606WA, kernel 6.17.0-20, ROCm 7.2.3 |
| AMD XDNA full SDK | Limited public access in 2026; Ryzen AI Software for Linux is Windows-first | https://ryzenai.docs.amd.com |

## Known workarounds

### Chrome APT `N: Skipping acquire … doesn't support architecture 'i386'`

The Google Chrome APT repo only distributes `amd64` packages but apt tries to fetch `i386` metadata too. Fix by pinning the architecture in the source file (idempotent; may revert on Chrome package reinstall):

```bash
sudo sed -i '/^Components:/a Architectures: amd64' /etc/apt/sources.list.d/google-chrome.sources
sudo apt update   # warning should be gone
```

## Variants we have not tested

- UM5606 with HX 365 (non-AI 9, 12C/24T but lower clocks)
- 24 GB RAM SKU (some regional variants)
- Non-OLED panel (rumored mid-2026 refresh)
- Strix Halo successor (different SoC, won't be UM5606 anyway)

If you have one of these, please open a hardware compatibility issue with `zenbook-validate` output attached.

# 08 — Troubleshooting

Common issues and fixes. Open an issue if you hit something not covered here.

## Kernel auto-upgraded past `6.17.0-20`

**Symptom:** `uname -r` shows `6.17.0-22+`, NPU stops working.

**Cause:** the `apt-mark hold` was removed (manually, by another script, or by `apt-get dist-upgrade --force`).

**Fix:**

```bash
# Reinstall pinned kernel
sudo apt install -y \
    linux-image-6.17.0-20-generic \
    linux-headers-6.17.0-20-generic \
    linux-modules-6.17.0-20-generic \
    linux-modules-extra-6.17.0-20-generic

# Re-hold
sudo apt-mark hold linux-image-generic linux-headers-generic linux-generic

# Update GRUB and reboot
sudo update-grub
sudo reboot
```

If `6.17.0-20` is no longer in the apt archive, see [`02-kernel-pinning.md`](02-kernel-pinning.md) for manual fallback options.

## Wayland session not active

**Symptom:** `echo $XDG_SESSION_TYPE` returns `x11`.

**Fix:**
1. Log out
2. At the login screen, click your username
3. Click the gear icon (bottom-right)
4. Select **Ubuntu (Wayland)**
5. Log in

If "Ubuntu (Wayland)" isn't listed, you might be on a non-GDM display manager — check `/etc/X11/default-display-manager`.

## Docker permission denied

**Symptom:** `docker run hello-world` returns `Got permission denied while trying to connect to the Docker daemon socket`.

**Fix:** your user isn't yet in the `docker` group, or you haven't started a fresh shell.

```bash
# Verify group membership
groups | grep docker

# If not present:
sudo usermod -aG docker $USER

# Apply without logging out
newgrp docker

# Or fully log out and back in
```

## Cursor won't launch

**Symptom:** `cursor` command not found, or GUI launches with errors.

**Fix:**

```bash
# Verify install
which cursor
dpkg -l cursor

# If missing, ensure apt repo is configured
ls /etc/apt/sources.list.d/cursor.list
sudo apt update
sudo apt install cursor

# Try launching from terminal to see errors
cursor

# If launches but blank window: usually a Wayland/EGL issue, try:
cursor --disable-gpu
# or set ELECTRON_OZONE_PLATFORM_HINT=auto in your shell
```

If you'd rather use the legacy AppImage (e.g. Cursor team retires the apt repo), grab it from cursor.com directly. The script no longer ships AppImage handling because the apt repo is now upstream-supported.

## `claude` CLI uses API instead of Pro/Max subscription

**Symptom:** Claude Code burns through quota fast and you're being billed via API instead of using your Pro plan.

**Cause:** an `ANTHROPIC_API_KEY` env var is set somewhere in your shell config.

**Fix:**

```bash
grep -rn "ANTHROPIC_API_KEY" ~/.bashrc ~/.zshrc ~/.profile ~/.bash_profile 2>/dev/null
# Remove any matching lines, then:
unset ANTHROPIC_API_KEY
claude logout
claude login   # follow the browser flow — picks up your subscription
```

## OnlyOffice doesn't open `.xlsx` macros

**Cause:** macro support requires OnlyOffice ≥ 7.x.

**Fix:**

```bash
flatpak update org.onlyoffice.desktopeditors
# Then in the GUI: Settings → Macro settings → Enable
```

## `restic` repo locked

**Symptom:** `restic backup` returns `repository is already locked`.

**Cause:** a previous run was killed mid-backup and didn't release the lock.

**Fix:**

```bash
restic -r <REPO> unlock
restic -r <REPO> snapshots   # verify
```

## Obsidian community plugins won't load

**Cause:** "Restricted mode" is enabled by default.

**Fix:**
1. Settings → Community plugins → Turn OFF "Restricted mode"
2. Re-enable each plugin individually
3. If still failing, check `<vault>/.obsidian/plugins/` permissions (should be owned by your user)

## LaTeX package missing

**Symptom:** `pdflatex` errors with `! LaTeX Error: File 'xxx.sty' not found.`

**Fix:** install `texlive-full` (~4 GB) — none of this repo's sections install LaTeX automatically because of the size:

```bash
sudo apt install -y texlive-full
```

For a single missing package:

```bash
tlmgr search --global --file "xxx.sty"
sudo tlmgr install <package_name>
```

## Steam doesn't see your AMD GPU

**Cause:** Vulkan stack incomplete, or you skipped Section 04 (extended apt).

**Fix:**

```bash
sudo apt install -y mesa-vulkan-drivers libvulkan1
vulkaninfo --summary   # confirm AMD Radeon shows up
```

## Battery drains while suspended

**Cause:** known firmware/UEFI issue on some Zenbook S16 BIOS revisions.

**Fix:**
1. Update BIOS via MyASUS (`flatpak install flathub com.asus.myasus` — works on Wayland with portal access) or boot Windows briefly to update via official tool
2. Check `/sys/power/mem_sleep` — should be `[s2idle]` or `deep`. Set the latter via kernel parameter `mem_sleep_default=deep` in `/etc/default/grub` if `s2idle` is power-hungry.

## Webcam quality looks washed out

This is hardware. The Zenbook S16's IR + RGB combo webcam is mediocre by design. For meetings, use:

- An external USB webcam (Logitech Brio, Razer Kiyo, etc)
- Phone-as-webcam apps: Camo, DroidCam, Iriun
- DSLR/mirrorless via gphoto2 + `v4l2loopback`

## Speaker quality is poor

Also hardware. Use headphones for important audio. The script doesn't try to "fix" this with EQ profiles — those tend to break harder than they help.

## Asking for help

When opening an issue:

```bash
# Generate a diagnostics bundle
zenbook-validate > /tmp/zenbook-diag.txt 2>&1
uname -a >> /tmp/zenbook-diag.txt
sudo dmidecode -t system | grep -E "Manufacturer|Product|Version|Serial" | head -20 >> /tmp/zenbook-diag.txt
sudo dmesg | grep -iE "amdxdna|amdgpu|radeon" | tail -50 >> /tmp/zenbook-diag.txt
```

Attach `/tmp/zenbook-diag.txt` to your issue (review it first — `dmidecode` may include serial numbers you'd rather not publish).

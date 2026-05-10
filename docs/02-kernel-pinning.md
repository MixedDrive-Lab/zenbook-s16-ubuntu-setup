# 02 — Kernel pinning for `amdxdna` NPU compatibility

## TL;DR

- The Zenbook S16's NPU is driven by the kernel module **`amdxdna`**.
- Mainline kernels **≥ 6.17.0-22** broke `amdxdna` due to a SVA / IOMMU change.
- Workaround: stay on **`linux-image-6.17.0-20-generic`** until upstream lands a fix.
- Section 02 of `setup.sh` does this for you and runs `apt-mark hold` so a future `apt upgrade` won't undo it.

## The bug

On a kernel ≥ 6.17.0-22, opening a userspace handle to the NPU fails with:

```
amdxdna_drm_open: SVA bind device failed, ret -95
```

`-95` is `EOPNOTSUPP`. The `amdxdna` driver tries to attach via [Shared Virtual Addressing](https://docs.kernel.org/userspace-api/iommu.html), but a recent commit — *"iommu: disable SVA when CONFIG_X86 is set"* — disables SVA on x86 unconditionally, so the bind never succeeds.

Without working SVA, no userspace tool can talk to the NPU: ROCm, AMD's XDNA runtime, anything built on top of it.

## What the script does

1. Reads `uname -r`. If you're already on `6.17.0-20-generic`, it just runs `apt-mark hold` and exits.
2. Otherwise it tries to install:
   - `linux-image-6.17.0-20-generic`
   - `linux-headers-6.17.0-20-generic`
   - `linux-modules-6.17.0-20-generic`
   - `linux-modules-extra-6.17.0-20-generic`
3. Runs `update-grub` so the new kernel is bootable.
4. **Sets `GRUB_DEFAULT` so `6.17.0-20-generic` boots automatically.** Three strategies, in order:
   - **A. Title-based** (default since v0.3.1): writes `GRUB_DEFAULT="<submenu_title>><entry_title>"` — e.g. `"Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-20-generic"`. Most readable + survives `update-grub` reordering.
   - **B. Menuentry-id** (fallback): `"<submenu_id>><menu_id>"`, e.g. `"gnulinux-advanced-UUID>gnulinux-6.17.0-20-generic-advanced-UUID"`.
   - **C. Position-pair** (last resort): `"1>N"` where `N` is the zero-indexed position inside the Advanced submenu.

   After writing, the script re-runs `update-grub` and **verifies** that `/etc/default/grub`'s `GRUB_DEFAULT` line now contains `6.17.0-20`. If not, sec 02 returns a non-zero exit code and Stage A's final banner switches to the **`MANUAL GRUB FIX NEEDED`** variant which prints a copy-pasteable `sed` command (see [Manual GRUB fix](#manual-grub-fix) below).
5. Runs `apt-mark hold` on `linux-image-generic`, `linux-headers-generic`, `linux-generic` so future `apt upgrade` won't replace your kernel with `-22+`.
6. Tells you to reboot.

After reboot, `uname -r` should report `6.17.0-20-generic`.

## Manual GRUB fix

If sec 02 reported "GRUB_DEFAULT could not be set automatically" (or `uname -r` after reboot still shows the wrong kernel), set the default by hand:

```bash
# 1. Inspect your menu structure to find the right titles:
sudo awk -F"'" '/menuentry|submenu/ && !/recovery/ {print NR": "$2}' /boot/grub/grub.cfg
# Expect output like:
#   150: Ubuntu                                            <- main entry (latest kernel)
#   162: Advanced options for Ubuntu                       <- submenu title
#   163: Ubuntu, with Linux 6.17.0-23-generic              <- inside submenu
#   190: Ubuntu, with Linux 6.17.0-20-generic              <- the one we want

# 2. Set GRUB_DEFAULT to "<submenu_title>><entry_title>".
# Note the literal '>' separator (NOT '>>').
sudo sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-20-generic"|' /etc/default/grub

# 3. Verify:
grep ^GRUB_DEFAULT /etc/default/grub

# 4. Apply + reboot:
sudo update-grub
sudo reboot

# 5. Verify after boot:
uname -r   # should show 6.17.0-20-generic
```

If your distro's submenu/entry titles are different (e.g. localized Ubuntu), substitute the actual values from step 1's output.

Alternative: at the GRUB boot menu, manually pick **Advanced options for Ubuntu → Ubuntu, with Linux 6.17.0-20-generic** every time. Tedious but doesn't require editing config.

## Manual fallback (kernel not in apt)

If `linux-image-6.17.0-20-generic` is no longer in your apt archive (it gets pruned eventually), you have three options:

### Option A — Ubuntu Mainline PPA

The kernel team publishes "mainline" builds at:

> https://kernel.ubuntu.com/~kernel-ppa/mainline/

Find a `v6.17-rc*` directory whose ABI matches `0-20`, download the four `.deb` files for `amd64`, then:

```bash
sudo dpkg -i \
    linux-headers-*_all.deb \
    linux-headers-*_amd64.deb \
    linux-image-unsigned-*_amd64.deb \
    linux-modules-*_amd64.deb
```

Note: mainline builds aren't signed for Secure Boot. Either disable SB or use an Ubuntu-signed build from option B.

### Option B — Launchpad publishing history

The Ubuntu archive's full publishing history:

> https://launchpad.net/ubuntu/+source/linux/+publishinghistory

Filter by series `noble` and you can find every `linux` source upload, including `6.17.0-20.20`. Click through to the binary `.deb` files for `amd64`.

### Option C — Custom build

Clone `kernel.ubuntu.com/ubuntu/+source/linux`, check out the `Ubuntu-6.17.0-20.20` tag, run the standard `fakeroot debian/rules binary-headers binary-generic`. Takes ~30 minutes on the Zenbook S16. Out of scope for this guide.

## Verifying the NPU works

After reboot, run `zenbook-validate` (generated by section 10). The `amdxdna NPU` block should show:

```
  ✓ lspci: AMD NPU detected (1022:17f0)
  ✓ lsmod: amdxdna module loaded
  ✓ /dev/accel populated
  ✓ dmesg: amdxdna entries present
```

If `dmesg` still has `SVA bind device failed`, you're not on the right kernel — check `uname -r`.

## When to undo the hold

Watch the LKML / `linux-iommu` threads. When the SVA-on-x86 issue is fixed and a kernel `≥ 6.17.0-22` ships with the fix, you can release:

```bash
sudo apt-mark unhold linux-image-generic linux-headers-generic linux-generic
sudo apt update && sudo apt full-upgrade
sudo reboot
```

Or just keep the hold — `6.17.0-20` will keep working as long as it does.

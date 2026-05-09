# 01 — Pre-install: Ubuntu on the Zenbook S16

This guide assumes you're starting from scratch (factory Windows or empty SSD). If you already have Ubuntu 24.04 running, skip ahead to [`02-kernel-pinning.md`](02-kernel-pinning.md).

## What you need

- A USB drive ≥ 8 GB
- Laptop charger plugged in (do not install on battery)
- Wired internet recommended (~5–15 GB downloaded depending on opt-in flags)
- A few hours

## 1. Download Ubuntu 24.04 LTS

```bash
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso
sha256sum ubuntu-24.04.1-desktop-amd64.iso
# Compare against https://releases.ubuntu.com/24.04/SHA256SUMS
```

Use the most recent 24.04.x point release — you'll be downgrading the kernel anyway in section 02.

## 2. Make a bootable USB

The official Ubuntu installer's recommendation is `balenaEtcher`, but `dd` works fine:

```bash
# Identify your USB device (often /dev/sdb or /dev/sdc)
lsblk

# Write (DOUBLE-CHECK the device — wrong target = data loss)
sudo dd if=ubuntu-24.04.1-desktop-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## 3. BIOS / UEFI settings

Reboot, hit **F2** at the ASUS splash to enter BIOS. Set:

| Setting | Value |
|---|---|
| Secure Boot | Disabled (or keep enabled if you'll only use signed kernels — but `apt-mark hold` and mainline kernels can complicate this) |
| Boot mode | UEFI |
| Fast Boot | Disabled |
| TPM | Enabled (for LUKS hardware-bound keys, optional) |

Save and exit. Tap **Esc** to enter the boot menu and boot from the USB.

## 4. Install Ubuntu

| Wizard step | Recommendation |
|---|---|
| Language | English (changes are easy later) |
| Keyboard | English (US) |
| Updates | "Normal installation" + "Download updates" + "Install third-party software" |
| Install type | "Erase disk and install Ubuntu" for a clean install, or "Something else" for custom partitioning |
| Encryption | LUKS recommended for any laptop you carry around |
| Timezone | Whatever applies |
| User | Create your user with a strong password |

### Partition recommendation

For a typical 1–4 TB NVMe single-disk install:

```
/boot/efi    1 GB     EFI System Partition
/            300 GB   ext4 (root)
/home        rest     ext4 (user data)
swap         32 GB    swap (matches RAM for hibernation; skip if you don't hibernate)
```

If you don't need hibernation, drop the swap partition and let `systemd-zram-generator` (Ubuntu default since 23.10) handle compressed RAM-backed swap.

## 5. First boot

1. Remove USB
2. Log in
3. Skip Ubuntu Pro
4. Skip data sharing
5. Apply any pending updates from Software Updater **but don't reboot yet** — the next step pins your kernel.

You're now ready for [`02-kernel-pinning.md`](02-kernel-pinning.md).

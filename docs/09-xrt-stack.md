# 09 — XRT NPU stack (`--with-xrt`)

The Zenbook S16 ships with an AMD XDNA 2 NPU (50 TOPS, identifies as PCI device `1022:17f0`). To use it from userspace you need the AMD XRT runtime + the XDNA plugin. This guide covers how to install them with `setup.sh`.

## Why this section is two-phase

Installing XRT requires a reboot in the middle:

1. **Section 11a** runs the `amdgpu-install` ROCm bootstrap and adds your user to the `render`/`video` groups. **Group membership only takes effect after re-login**, so a reboot is required.
2. **Section 11b** installs the four XRT `.deb` files and configures your shell. It refuses to run until the prep phase has been completed and the groups are active.

State is tracked at `~/.cache/zenbook-s16-setup/xrt-prep-done` and `~/.../xrt-install-done`.

## What you need to download manually

The XRT `.deb` files are part of the **AMD Ryzen AI Software** distribution. They are EULA-gated — there is no public direct URL — so the script cannot fetch them for you. You need to:

1. Visit https://www.amd.com/en/developer/resources/ryzen-ai-software.html
2. Sign in with an AMD account, accept the EULA
3. Download the Linux driver bundle, e.g. `ryzen_ai-1.7.1.tgz`
4. Extract it: `tar -xzf ryzen_ai-1.7.1.tgz`
5. Inside the extracted folder, find the four `.deb` files:
   - `xrt_<version>_24.04-amd64-base.deb`
   - `xrt_<version>_24.04-amd64-base-dev.deb`
   - `xrt_<version>_24.04-amd64-npu.deb`
   - `xrt_plugin.<version>_24.04-amd64-amdxdna.deb`
6. Copy them into `~/Downloads/xrt-bundle/` (or any directory you point `XRT_BUNDLE_DIR` at)

The `amdgpu-install_*.deb` is **not** EULA-gated and the script will auto-download the latest version from `repo.radeon.com/amdgpu-install/latest/ubuntu/noble/` if you don't drop one in the bundle yourself.

## Running it

After the manual download, the typical flow is:

```bash
# Phase 1 — pre-reboot prep
./scripts/setup.sh --with-xrt
# This will:
#   1. Verify kernel 6.17.0-20-generic is booted
#   2. Auto-download amdgpu-install_*.deb (or use one in the bundle)
#   3. Run `amdgpu-install --usecase=rocm,hiplibsdk --no-dkms`
#   4. Add your user to render+video groups
#   5. Print a "REBOOT REQUIRED" banner, exit

# Reboot
sudo reboot

# Phase 2 — post-reboot install
./scripts/setup.sh --with-xrt
# This will detect that 11a is done and run 11b instead:
#   1. Verify render+video are active in your login
#   2. Install the four XRT .deb files in the right order
#   3. Append `source /opt/xilinx/xrt/setup.sh` to ~/.bashrc
#   4. Configure /etc/security/limits.d/99-amdxdna.conf for memlock unlimited
#   5. Run `xrt-smi examine` to verify the NPU is detected
```

You can also run the phases explicitly:

```bash
./scripts/setup.sh --section 11a   # prep, then reboot
./scripts/setup.sh --section 11b   # install + verify
```

## What gets installed

After 11b completes:

| Path | What | Source |
|---|---|---|
| `/opt/xilinx/xrt/` | XRT runtime (libs, tools, headers) | `xrt_*_base.deb` + `xrt_*_base-dev.deb` |
| `/opt/xilinx/xrt/bin/xrt-smi` | NPU diagnostic CLI | (installed by base) |
| `/opt/xilinx/xrt/bin/xclbinutil` | xclbin binary inspection | (installed by base) |
| `/opt/xilinx/xrt/lib/libxrt_*.so*` | XRT SHIM library + amdxdna plugin | `xrt_*_npu.deb` + `xrt_plugin*amdxdna.deb` |
| `/lib/modules/.../amdxdna.ko*` | XDNA kernel module (DKMS) | `xrt_plugin*amdxdna.deb` |
| `/usr/lib/firmware/amdnpu/` | NPU firmware blobs | `xrt_plugin*amdxdna.deb` |
| `/etc/security/limits.d/99-amdxdna.conf` | memlock unlimited (per AMD docs) | written by 11b |
| `~/.bashrc` | `source /opt/xilinx/xrt/setup.sh` snippet | appended by 11b |

ROCm gets installed too (because of `--usecase=rocm,hiplibsdk`), under `/opt/rocm/`.

## Verifying the install

```bash
# Quick: zenbook-validate covers the full stack
zenbook-validate

# Deep: run the manual checks AMD documents
sudo /opt/xilinx/xrt/bin/xrt-smi examine
lspci -d 1022: | grep -i signal       # NPU PCI device 1022:17f0
lsmod | grep amdxdna                   # kernel module loaded
ls -la /dev/accel/                     # accel0 should exist
sudo dmesg | grep -E "amdxdna|NPU"     # no SVA bind errors
```

A healthy install on the Zenbook S16 gives:

```
$ sudo xrt-smi examine
System Configuration
  ...
Device(s) Present
|BDF            |Name      |
|---------------|----------|
|[0000:c5:00.1] |NPU Strix |
```

`Strix` is the architecture codename for Ryzen AI 9 HX 370. Other Strix Point chips will show similarly.

## Troubleshooting

### `amdxdna_drm_open: SVA bind device failed, ret -95`

You're on a kernel ≥ 6.17.0-22. Re-run Section 02 to pin to `6.17.0-20-generic`, reboot, then re-run 11b. See `docs/02-kernel-pinning.md`.

### `xrt-smi examine` says no devices

Check, in order:

1. `uname -r` — must be `6.17.0-20-generic`
2. `lsmod | grep amdxdna` — module loaded?
3. `id -nG | grep -E 'render|video'` — both groups present?
4. BIOS: NPU/IPU enabled? Some ASUS BIOS revisions disable it by default. F2 at boot → Advanced → CPU Configuration → IPU → Enabled.

### Section 11a fails on `amdgpu-install` with apt errors

Old `amdgpu` or `rocm` repo files in `/etc/apt/sources.list.d/` can conflict with the new install. The script warns about these in the pre-check; review and remove conflicting entries before retrying.

### "GPG error: ... `https://repo.radeon.com/amdgpu/X.Y/ubuntu noble Release` does not have a Release file"

Known transient AMD repo issue. The error often resolves itself on the next `apt update`; if it persists, comment out the offending line in `/etc/apt/sources.list.d/amdgpu.list` and re-run.

### `apt install --fix-broken` fails on the XRT plugin .deb

The DKMS module compile may be failing against your held kernel. Check `/var/lib/dkms/<package>/build/make.log`. A common cause is missing `linux-headers-6.17.0-20-generic`; install it with:

```bash
sudo apt install -y linux-headers-6.17.0-20-generic
```

Then re-run `--section 11b`.

### `rocminfo` fails with `HSA_STATUS_ERROR_INVALID_ARGUMENT` after XRT install

XRT's `setup.sh` sets `LD_LIBRARY_PATH=/opt/xilinx/xrt/lib:...`. Since `LD_LIBRARY_PATH` overrides a binary's embedded `RUNPATH`, ROCm tools like `rocminfo` end up loading the Ubuntu-packaged `libhsa-runtime64` from `/lib/x86_64-linux-gnu` instead of the ROCm 7.x version from `/opt/rocm/lib`. These are different builds and the wrong one triggers `HSA_STATUS_ERROR_INVALID_ARGUMENT`.

Section 11b (v0.3.11+) automatically writes `/opt/rocm/lib` to `LD_LIBRARY_PATH` after the XRT source line. To fix an existing `~/.bashrc` manually:

```bash
# Remove the old stale line (written by v0.3.10 and earlier)
sed -i '/export LD_LIBRARY_PATH=\/lib\/x86_64-linux-gnu/d' ~/.bashrc

# Add ROCm priority (append to the XRT block or at end of file)
echo 'export LD_LIBRARY_PATH=/opt/rocm/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}' >> ~/.bashrc

# Verify in a fresh shell
bash -i -c 'rocminfo 2>&1 | grep -E "Agent|gfx|Device Type"'
```

Or re-run `./scripts/setup.sh --section 11b` — it detects the old line, removes it, and appends the fix.

### `amdxdna: xdna_mailbox … Message callback ret -22 / disable irq` in dmesg

This is a **cosmetic warning**, not a functional error. The text `disable irq` is a leftover log message string — the actual `disable_irq()` call was removed in the kernel patch `cd740b873` ("accel/amdxdna: Check interrupt register before mailbox_rx_worker exits"), backported to 6.14 and included in 6.17. The NPU IRQ is **not** being disabled despite the message. The underlying race condition (firmware responding right after the driver clears the interrupt register) still triggers occasionally but is handled gracefully — the IRQ stays active and the NPU remains functional.

## Alternative: build XRT from source (no AMD account needed)

Building from `amd/xdna-driver` source skips the AMD account requirement and produces a newer version (2.23+) than the EULA-gated bundle (2.21). **This is now the recommended path** — the source-built version unlocks the GEMM and throughput tests in `xrt-smi validate`.

```bash
git clone https://github.com/amd/xdna-driver.git ~/xdna-driver
cd ~/xdna-driver
git submodule update --init --recursive
sudo ./tools/amdxdna_deps.sh          # installs ~60 build deps

# 1. Build XRT base packages
cd xrt/build
./build.sh -npu -opt                  # ~5-15 min
cd Release
cpack -G DEB                          # generates xrt_*.deb files
cd ../../..

# 2. Build the XDNA plugin package
cd build
./build.sh -release                   # ~3-5 min
cd ..

# 3. Install everything in one transaction
sudo apt install \
    xrt/build/Release/xrt_*_24.04-amd64-base.deb \
    xrt/build/Release/xrt_*_24.04-amd64-npu.deb \
    build/Release/xrt_plugin.*_24.04-amd64-amdxdna.deb
# DKMS builds and loads amdxdna.ko automatically on install

# 4. If multiple kernels are installed, build DKMS for each one
# The apt install step only builds for the running kernel.
for kver in $(ls /lib/modules/); do
    [[ "$kver" == "$(uname -r)" ]] && continue   # already built
    sudo dkms install xrt-amdxdna/"$(dkms status | grep xrt-amdxdna | awk -F',' '{print $1}' | awk '{print $2}')" -k "$kver"
done
```

This installs XRT 2.23+ with the full HWCTX feature set. `xrt-smi validate` should show all three tests passing (gemm: ~51 TOPS, latency: ~80 µs, throughput: ~58k–64k op/s).

## Removing XRT

```bash
# Uninstall packages (in reverse dependency order)
sudo apt remove --purge xrt-amd-aie-npu xrt-amd-aie xrt
sudo amdgpu-uninstall    # removes ROCm
sudo apt autoremove

# Remove config additions
sudo rm /etc/security/limits.d/99-amdxdna.conf

# Remove ~/.bashrc snippet (manual edit)
${EDITOR:-nano} ~/.bashrc   # delete the "Added by zenbook-s16-ubuntu-setup (Section 11b — XRT)" block

# Clear state files
rm -f ~/.cache/zenbook-s16-setup/xrt-{prep,install}-done
```

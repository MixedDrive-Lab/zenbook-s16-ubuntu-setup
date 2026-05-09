---
name: Hardware compatibility report
about: Report results on a different Zenbook S16 revision or similar AMD Ryzen AI laptop
title: '[HW] '
labels: hardware-compat
assignees: ''
---

## Hardware

| Field | Value |
|---|---|
| Model | <!-- e.g. ASUS Zenbook S16 UM5606HA --> |
| CPU | <!-- e.g. Ryzen AI 9 HX 370 / HX 365 / 9 365 --> |
| GPU | <!-- e.g. Radeon 890M / 880M --> |
| RAM | <!-- e.g. 32GB / 24GB LPDDR5X --> |
| SSD | <!-- e.g. 1TB / 2TB / 4TB --> |
| Display | <!-- e.g. 3K OLED 120Hz / 2.5K IPS --> |
| BIOS | <!-- version, e.g. 304 --> |

## Result

- [ ] Setup script ran end-to-end with no errors
- [ ] Kernel pinning to 6.17.0-20 worked
- [ ] NPU detected after reboot (`zenbook-validate` shows all 4 amdxdna checks passing)
- [ ] Vulkan/GPU stack works
- [ ] Flatpak apps work (if installed)
- [ ] Docker hello-world works
- [ ] Wayland session active

## What worked / didn't

<!--
Free-form. Especially valuable:
  * Was 6.17.0-20-generic still in apt? Did you have to fall back?
  * Anything specific to your hardware variant?
  * Any quirk that should go in docs/hardware-quirks.md?
-->

## `zenbook-validate` output

```
<paste full output>
```

## Setup log excerpts

```
<any [ERROR] lines from ~/.cache/zenbook-s16-setup/setup-*.log>
```

## Suggested doc/script changes

<!-- Optional. If you fixed something locally, what should the repo do differently? -->

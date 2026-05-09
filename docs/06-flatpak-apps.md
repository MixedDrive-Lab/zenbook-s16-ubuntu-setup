# 06 — Flatpak apps (`--with-flatpak`)

## Why Flatpak instead of apt for these

| Reason | What it buys you |
|---|---|
| Codec freshness | Audacity, GIMP, VLC, HandBrake, Kdenlive get newer codec/format support than Ubuntu's archive ships |
| Sandboxing | Closed-source comms apps (Spotify, Discord, Zoom) run in a confined environment — they can't read `~/personal-journal/` unless you grant access via Flatseal |
| No conflict with system ffmpeg | Apt versions of these media tools sometimes pin specific `ffmpeg`/codec versions; Flatpak isolates them |
| Faster upstream releases | Especially OnlyOffice and Obsidian — Flatpak builds are usually current within a week of upstream |

The trade-off: Flatpak apps are larger on disk (each pulls a runtime) and a tiny bit slower to launch. On a Zenbook S16 with 32 GB RAM and a 4 TB NVMe, neither matters.

## What gets installed

### Productivity

| App ID | Why |
|---|---|
| `org.onlyoffice.desktopeditors` | Best `.docx` / `.xlsx` / `.pptx` fidelity on Linux. Better than LibreOffice for complex Excel files (macros, conditional formatting, pivot tables). |
| `md.obsidian.Obsidian` | Markdown-based knowledge management with a plugin ecosystem. Local-first, no cloud lock-in. |

### Media

| App ID | Use |
|---|---|
| `org.audacityteam.Audacity` | Audio editor / cleanup |
| `org.gimp.GIMP` | Raster image editor |
| `com.github.PintaProject.Pinta` | Quick sketches (Paint.NET-style, lighter than GIMP) |
| `org.videolan.VLC` | Plays anything |
| `fr.handbrake.ghb` | Video transcoding |
| `org.kde.kdenlive` | Non-linear video editor |

### Comms

| App ID | Use |
|---|---|
| `com.spotify.Client` | Music streaming |
| `com.discordapp.Discord` | Voice/chat |
| `us.zoom.Zoom` | Video meetings (corporate) |

## Permissions

Comms apps default to broad sandbox permissions. Tighten with [**Flatseal**](https://flathub.org/apps/com.github.tchx84.Flatseal):

```bash
sudo flatpak install -y flathub com.github.tchx84.Flatseal
```

Useful tightenings:

| App | Revoke | Why |
|---|---|---|
| Discord | `Filesystem → Home` | Reduce blast radius if compromised |
| Zoom    | `Filesystem → Home` | Same — Zoom only needs access to its own config |
| Spotify | All filesystem access | Streaming app doesn't need home access |

For OnlyOffice and Obsidian you generally **want** filesystem access — they're working with your documents.

## Updating

```bash
flatpak update -y
```

Run weekly or set up a cron entry:

```bash
echo "0 5 * * 0 flatpak update --noninteractive --assumeyes" | crontab -
```

## Removing

```bash
flatpak uninstall com.example.App
flatpak uninstall --unused      # cleans orphaned runtimes
```

## When to skip Section 08

- You don't use any of the listed apps
- You prefer apt versions of media tools (some users still do — `apt install audacity gimp vlc kdenlive` works)
- You're on a metered connection (Flatpak runtimes are 1–2 GB initial download)

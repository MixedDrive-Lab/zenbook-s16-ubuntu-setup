# 05 — Apps catalog (`--with-apps` and `--with-ai-stack`)

These two flags pull in the optional applications. Mix of open source and proprietary — read before running.

## `--with-ai-stack` (Section 06)

| App | License | Why include | Free alternative |
|---|---|---|---|
| **Cursor** | Proprietary, freemium | AI-first VS Code fork. Strong if you live in the editor. | VS Code + Continue extension, VSCodium |
| **Warp Terminal** | Proprietary, freemium | Modern terminal with AI suggestions. Block-based output. | `kitty`, `wezterm`, `alacritty`, `ghostty` |
| **Node.js 22 LTS** | Open source | Required by Claude Code CLI; useful for any JS work | — |
| **Claude Code CLI** | Proprietary (npm: `@anthropic-ai/claude-code`) | Anthropic's terminal AI agent | OpenAI Codex CLI, `aider`, `goose`, etc |

If you'd rather stay open-source-only, **skip this flag** and install your preferred alternatives manually.

After install, sign in:

```bash
# Cursor: launches GUI flow
cursor

# Claude Code: triggers browser auth
claude login

# Warp: GUI sign-in on first launch
warp-terminal
```

## `--with-apps` (Section 07)

| App | License | Why |
|---|---|---|
| **1Password** | Proprietary, paid | Password manager with strong Linux support. Required if you're rotating to multi-machine + cloud workflow. | Bitwarden (free, FOSS) |
| **Google Chrome** | Proprietary | TVS / corporate testing primary, browser extension parity | Chromium, Brave |
| **LocalSend** | FOSS (MIT) | AirDrop alternative — phone ↔ laptop ↔ tablet over WiFi | Snapdrop, magic-wormhole |
| **Typora** | Proprietary, paid | Markdown WYSIWYG editor — clean PDF/HTML export | Mark Text (FOSS), Obsidian (free) |
| **Gum** | FOSS (MIT) | Pretty CLI prompts for shell scripts | `dialog`, `whiptail`, raw `read` |
| **LazyGit** | FOSS (MIT) | Git TUI — much faster than CLI for staging/log/rebase | `tig`, `gitui` |
| **LazyDocker** | FOSS (MIT) | Docker TUI — containers/images/volumes/networks at a glance | `ctop`, raw `docker` CLI |
| **Ulauncher** | FOSS (GPL) | App launcher with extension system | GNOME Activities, Albert, Rofi |

### Per-app quick start

**1Password**
1. Open from Activities → "Sign in to existing account"
2. Browser extension: install from Chrome Web Store
3. Verify: `op --version` if the CLI was bundled

**LocalSend**
1. Open → set device alias (e.g. `zenbook-yourname`)
2. Allow the firewall prompt for port `53317`
3. Install LocalSend on your phone (iOS/Android both available)
4. Pair: both devices on the same WiFi → "Send" tab → tap target

**Typora**
- Settings → Appearance → pick a theme (`Whitey` is good for PDF export)
- Use **only** for standalone `.md` files — pointing it at an Obsidian vault breaks plugin metadata

**LazyGit / LazyDocker**
- Just run `lazygit` in any git repo, `lazydocker` anywhere
- `?` opens contextual help inside the TUI

**Ulauncher**
- Settings → bind hotkey (most people use `Ctrl+Space`)
- Enable autostart so it survives login
- Browse extensions: clipboard manager, calculator, currency converter, etc

## Removing later

```bash
# Most are apt packages
sudo apt remove 1password google-chrome-stable typora ulauncher localsend

# Standalone binaries
sudo rm /usr/local/bin/{lazygit,lazydocker,gum}

# Cursor (apt-installed)
sudo apt remove cursor

# Claude Code CLI
sudo npm uninstall -g @anthropic-ai/claude-code
```

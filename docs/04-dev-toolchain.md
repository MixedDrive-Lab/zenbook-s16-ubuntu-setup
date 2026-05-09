# 04 — Dev toolchain: `mise` + Docker

## `mise`

> `mise` (pronounced *meez*) is a single-binary version manager that replaces `nvm`, `pyenv`, `rbenv`, `goenv`, `asdf`, etc. Written in Rust → 10–30 ms shell startup vs 200–500 ms for `asdf`.

Section 05 installs `mise` from its official APT repo (https://mise.jdx.dev/deb), adds the activation hook to `~/.bashrc`, and writes an empty `~/.config/mise/config.toml`.

### Adding languages

By default, Section 05 installs only the `mise` binary itself — no languages. You have two paths:

**Path A — manual, language-by-language (recommended for most users):**

```bash
# Phase A baseline (most common)
mise use --global python@3.12
mise use --global node@lts

# Add as needed
mise use --global rust@latest
mise use --global go@latest
mise use --global java@21
mise use --global ruby@3.3
mise use --global php@8.3
mise use --global erlang@latest
mise use --global elixir@latest
```

`mise install` will fetch + build everything declared in your global config.

**Path B — bulk install via Section 12 (`--with-mise-defaults`):**

For a turn-key "install all common languages" experience:

```bash
./scripts/setup.sh --with-mise-defaults
```

This installs **8 default languages** in one go:

| Language | Method | Version | Caveat |
|---|---|---|---|
| Node.js | mise | `lts` | safe |
| Go | mise | `latest` | safe (Go is backward-compatible) |
| Python | mise | `3.12` (default), `3.13`, `latest` | All three installed side-by-side. Default `python` resolves to 3.12 (broadest SLAM/CV compat — OpenCV bindings, Open3D, ORB-SLAM3 wrappers all stable on 3.12). Per-project override via `.mise.toml`. **`uv` (Astral) auto-installed** into the default Python via `pip install --user uv` — covers `uv venv`, `uv pip`, `uv add`, `uv run`. |
| Java | mise | `21` (LTS default), `latest` | Both installed. Default `java` resolves to 21 (current LTS, broadest ecosystem support: Spring Boot, Maven Central, Android tooling, JetBrains stack). `latest` for bleeding-edge experiments via `.mise.toml` override. |
| Ruby | mise | `latest` | also installs `gem install rails --no-document` (heavy: ~70 deps). Skip via manual path if you don't want Rails. |
| Erlang | mise | `latest` | ⚠️ **builds from source — 15-30 minutes** on a Zenbook S16. Build deps installed first via apt. |
| Elixir | mise | `latest` | depends on Erlang; Hex package manager (`mix local.hex`) installed automatically. |
| PHP | apt + Composer | system PHP + `php-{curl,apcu,intl,mbstring,opcache,pgsql,mysql,sqlite3,redis,xml,zip}` | mise's PHP plugin requires re-builds for extensions; apt is more practical. Composer installed to `/usr/local/bin/composer`. |
| Rust | rustup | `stable` | ⚠️ installed via canonical [`rustup`](https://rustup.rs/), **outside mise**. mise's Rust plugin is not used. cargo/rustc/rustup live in `~/.cargo/`. |

The flag is **opt-in** and **idempotent** — re-running it skips already-installed tools.

`--all` does **not** include `--with-mise-defaults` — install it explicitly because of the long-running Erlang build and the heavy Rails install.

#### When to skip Section 12

- You only need 1-2 specific languages → Path A is faster
- You want LTS-pinned versions → Path A with explicit version specs
- You're on a slow network or thermally-constrained → Erlang OTP build is brutal
- You're allergic to Rails being installed for Ruby → use Path A and skip the `gem install rails` step

### Per-project versions

Drop a `.mise.toml` in any project root:

```toml
[tools]
python = "3.13"
node = "20.11.0"
```

When you `cd` into the directory, `mise` switches to those versions automatically (assuming the path is in `trusted_config_paths` — first time you `cd` in, run `mise trust .`).

### Python multi-version workflow + `uv`

After Section 12, you have **3 Python interpreters** ready:

```bash
mise ls | grep python
# python  3.12.X       (default — what `python` resolves to)
# python  3.13.X
# python  latest       (3.14.X or whatever's newest)
```

To use a specific version in a project:

```bash
cd ~/projects/my-bleeding-edge-project/
echo '[tools]
python = "latest"
' > .mise.toml
mise trust .

# Now `python` here is the latest, but in other dirs still 3.12
python --version
```

**`uv` (Astral)** is installed into the default Python and replaces `python -m venv` + `pip` + `pip-tools`. Speed difference: `uv venv` ~50ms vs `python -m venv` ~1500ms. Workflow:

```bash
# Create a venv in the current directory (uses default Python = 3.12)
uv venv

# Or with a specific Python version mise has installed:
uv venv --python 3.13

# Install packages (much faster than pip):
uv pip install numpy opencv-python

# Activate the venv conventionally:
source .venv/bin/activate

# Or run a script in the venv without activating:
uv run python my_script.py

# Modern dependency management (replaces requirements.txt + pip-compile):
uv init             # creates pyproject.toml
uv add numpy        # adds to pyproject.toml + lockfile
uv sync             # install everything from lockfile
```

If `uv` isn't on PATH after Section 12, check `~/.local/bin/` is in `$PATH` (Ubuntu adds it via `~/.profile` by default). `uv --version` confirms install.

### Why `gfortran` is via apt, not `mise`

`gfortran` is part of GCC and lives at the system level. `mise`'s plugin ecosystem doesn't manage GCC versions cleanly. Section 03 installs `gfortran` via apt; if you need a specific version, build GCC from source or use Spack.

### Useful commands

```bash
mise ls                        # list installed tools
mise ls-remote python          # all available versions of Python
mise outdated                  # what could be updated?
mise self-update               # update mise itself
mise doctor                    # diagnose
```

## Docker

Section 05 installs Docker CE from the official `download.docker.com` repo, plus:

- `docker-buildx-plugin` (multi-arch builds, advanced caching)
- `docker-compose-plugin` (Compose v2, called as `docker compose`)
- `docker-ce-rootless-extras` (rootless mode, optional)

It also:

1. Adds your user to the `docker` group → log out + back in (or `newgrp docker`) for it to take effect
2. Writes `/etc/docker/daemon.json` with sane log rotation:
   ```json
   {
     "log-driver": "json-file",
     "log-opts": { "max-size": "10m", "max-file": "5" },
     "storage-driver": "overlay2"
   }
   ```
3. Restarts the daemon

### Smoke test

```bash
docker run --rm hello-world
docker compose version
```

### GPU passthrough (AMD)

Docker on AMD GPU isn't as turnkey as `nvidia-docker`. For containerized GPU workloads you'll typically:

```bash
docker run --rm \
    --device=/dev/kfd \
    --device=/dev/dri \
    --group-add video \
    rocm/dev-ubuntu-24.04 rocminfo
```

Out of scope for this repo — start with the [ROCm Docker docs](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/3rd-party/docker.html).

## When to skip Section 05

If you're already running everything via `nix`, `pixi`, `pkgsrc`, or you have very specific Docker requirements (e.g. `podman` instead of `docker`), pass `--section 03` and `--section 04` instead of running the default flow.

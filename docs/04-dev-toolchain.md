# 04 — Dev toolchain: `mise` + Docker

## `mise`

> `mise` (pronounced *meez*) is a single-binary version manager that replaces `nvm`, `pyenv`, `rbenv`, `goenv`, `asdf`, etc. Written in Rust → 10–30 ms shell startup vs 200–500 ms for `asdf`.

Section 05 installs `mise` from its official APT repo (https://mise.jdx.dev/deb), adds the activation hook to `~/.bashrc`, and writes an empty `~/.config/mise/config.toml`.

### Adding languages

The script does **not** install any languages by default. Pick what you actually need:

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

### Per-project versions

Drop a `.mise.toml` in any project root:

```toml
[tools]
python = "3.11.9"
node = "20.11.0"
```

When you `cd` into the directory, `mise` switches to those versions automatically (assuming the path is in `trusted_config_paths` — first time you `cd` in, run `mise trust .`).

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

# STRMProbe

**Make Sonarr/Radarr (and friends) read media info from `.strm` files.**

STRMProbe is a tiny `ffprobe` wrapper for LinuxServer.io (LSIO) Docker images. It
lets Sonarr, Radarr, Lidarr, Bazarr, Whisparr, Readarr — anything that shells out
to `ffprobe` — extract codec, resolution, duration and audio info from `.strm`
files, without modifying the apps themselves.

## The problem

A `.strm` file is plain text containing a streaming URL, e.g.:

```
http://nzbdav.example.local:3000/view/.ids/f/0/.../00000000-...?downloadKey=...&extension=mkv
```

Sonarr/Radarr call `ffprobe` on every imported file to read media info. On a
`.strm` file `ffprobe` reads *text* instead of a media container and fails:

```
ERROR VideoFileInfoReader: Unable to parse media info from file: ...mkv.strm
ffprobe exited with non-zero exit-code (1 - ...mkv.strm: Invalid data found when processing input)
```

Worse, the `ffprobe` shipped in LSIO images is deliberately built
`--disable-network` (`Input: file` only), so even pointing it at the URL would
fail with `Protocol not found`.

## How it works

STRMProbe replaces `/app/<app>/bin/ffprobe` with a wrapper and keeps the original
as `ffprobe.real`:

- **`.strm` input** → the wrapper reads the URL from the file and probes it with a
  **network-capable** static `ffprobe` (`ffprobe-full`), injecting
  `-protocol_whitelist file,http,https,tcp,tls -analyzeduration 5000000 -probesize 5000000`.
- **Everything else** (normal media files, `-version`, `pipe:0`, …) → passed
  through to `ffprobe.real`, unchanged.

The apps see valid `ffprobe` JSON for `.strm` files and store media info normally.

A LinuxServer.io [`custom-cont-init.d`](https://docs.linuxserver.io/general/container-customization/)
script re-installs the wrapper on every container start, so image updates don't
break it. It also auto-downloads `ffprobe-full` if it's missing.

```
ffprobe <args> ──► ffprobe-wrapper.sh ──┬─ .strm? ─► ffprobe-full  (probes the URL over HTTP)
                                         └─ else   ─► ffprobe.real  (original LSIO binary)
```

### Wrapper-source lookup order

The init script (`strmprobe-init.sh`) looks for the wrapper source in this order
on every container start:

1. `$STRMPROBE_WRAPPER_SRC` (if set as environment variable)
2. `/config/strmprobe/ffprobe-wrapper.sh` (manual install convention)
3. `/usr/local/share/strmprobe/ffprobe-wrapper.sh` (Docker mod convention)

The first existing path wins. This is what lets the Docker mod work out of the
box without requiring users to set `STRMPROBE_WRAPPER_SRC`, while still allowing
manual installs to keep using `/config/strmprobe/`.

## Repository layout

| Path | Purpose |
|---|---|
| `src/ffprobe-wrapper.sh` | the wrapper that replaces `/app/<app>/bin/ffprobe` |
| `src/strmprobe-init.sh` | `custom-cont-init.d` script: auto-detect apps, back up, install, auto-download |
| `scripts/fetch-ffprobe-full.sh` | standalone helper to download + verify `ffprobe-full` (host use) |
| `scripts/health-check.sh` | check a running container is correctly patched |
| `tests/` | self-contained bash test suite (no real binaries needed) |
| `examples/` | docker-compose examples + Unraid notes |
| `mod/` | LinuxServer.io Docker mod (Dockerfile + staging/build scripts) |
| `.github/workflows/build-mod.yml` | CI: build + push the multi-arch mod image to GHCR |

## Installation (Docker mod — recommended)

Activate STRMProbe in any LSIO container with a single environment variable — no
volume mounts, symlinks or pre-seeding:

```yaml
services:
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    environment:
      - PUID=99
      - PGID=100
      - TZ=Europe/Berlin
      - DOCKER_MODS=ghcr.io/cosmicflow2512/strmprobe-mod:latest
      - STRMPROBE_LOG=1            # optional debug log
    volumes:
      - /path/to/sonarr/config:/config
      - /path/to/tv:/tv
    ports:
      - 8989:8989
```

On first start LSIO downloads the mod and overlays the init script
(`/custom-cont-init.d/99-strmprobe`) and the wrapper
(`/usr/local/share/strmprobe/ffprobe-wrapper.sh`) onto the container. The init
script then runs as root: backs up the original `ffprobe` to `ffprobe.real`,
installs the wrapper, and downloads `ffprobe-full`. Watch it with
`docker logs <app> | grep STRMProbe`.

> **Pin a version in production.** `:latest` always tracks `main`; pin a release
> tag (`:vX.Y.Z`) so mod updates don't roll out to you unexpectedly.

**Combining mods** — separate multiple mods with `|`:

```yaml
- DOCKER_MODS=ghcr.io/cosmicflow2512/strmprobe-mod:latest|linuxserver/mods:universal-package-install
```

STRMProbe's init script is numbered `99-` so it runs **last** — after any mod
that might also touch `/app/*/bin/`. (Mod load order is not otherwise guaranteed.)

## Manual installation (non-mod fallback)

For non-LSIO images, custom builds, or if you'd rather not use a mod, mount three
things into the container:

1. **Init script** — `src/strmprobe-init.sh` named `99-strmprobe`, mounted into
   the container at **`/custom-cont-init.d`** (container root, **not** inside
   `/config`). The file must be owned by `root:root` and executable (`chmod 755`);
   LSIO ignores files in this directory that aren't root-owned and executable.
2. **Wrapper source** — `src/ffprobe-wrapper.sh` placed at
   `/config/strmprobe/ffprobe-wrapper.sh` (read by the init script at startup).
3. **`ffprobe-full` binary** — *(optional)* `/config/bin/ffprobe-full`. Otherwise
   it's auto-downloaded on first start (needs container network access).
   Pre-seeding it from the host skips that download — handy if the container has
   no outbound network:
   ```bash
   bash scripts/fetch-ffprobe-full.sh /path/to/sonarr/config/bin/ffprobe-full
   ```

See [`examples/docker-compose.sonarr.yml`](examples/docker-compose.sonarr.yml)
and [`examples/unraid-notes.md`](examples/unraid-notes.md) for concrete wiring.
After mounting/copying, restart the container.

> **Installation order matters.** Keep the high number (`99-strmprobe`): LSIO runs
> `custom-cont-init.d` scripts alphabetically, so it ensures STRMProbe runs after
> other mods that might also modify `/app/*/bin/`.

> **Why not in `/config`?** LSIO explicitly does not support mounting custom
> scripts inside `/config`: *"we do not support mounting folders for custom
> scripts and services if they sit within the same folder that you are mounting
> for /config"* — [LSIO docs](https://docs.linuxserver.io/general/container-customization/).
> Mount the host directory directly to `/custom-cont-init.d`.

## Building the mod yourself

For forks or local testing:

```bash
bash mod/build.sh                 # stages src/ -> mod/root/ and builds strmprobe-mod:test
```

`src/` stays the single source of truth — `mod/stage.sh` copies the wrapper and
init script into `mod/root/` (git-ignored) at build time. CI builds and pushes
**multi-arch (amd64 + arm64)** images to GHCR on every push to `main` touching
`src/` or `mod/`, via
[`.github/workflows/build-mod.yml`](.github/workflows/build-mod.yml). After the
first push, set the GHCR package visibility to **public** so users can pull it
without authenticating.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `STRMPROBE_LOG` | `0` | `1` enables the wrapper debug log |
| `STRMPROBE_LOGFILE` | `/config/logs/ffprobe-wrapper.log` | log destination |
| `STRMPROBE_LOG_MAX` | `1048576` | log size cap in bytes (truncates in place) |
| `STRMPROBE_FULL` | `/config/bin/ffprobe-full` | path to the network-capable ffprobe |
| `STRMPROBE_REAL` | `<bindir>/ffprobe.real` | path to the original ffprobe |
| `STRMPROBE_WRAPPER_SRC` | *auto-detect* | wrapper source the init script installs; if unset, the init script checks `/config/strmprobe/ffprobe-wrapper.sh` (manual install) and `/usr/local/share/strmprobe/ffprobe-wrapper.sh` (Docker mod) in order |
| `STRMPROBE_CACHE_DIR` | *(unset = off)* | if set, cache successful `.strm` probe results here to skip repeat downloads (see [Result cache](#result-cache-optional)) |

## Verifying

```bash
# Wrapper active + version
docker exec sonarr /app/sonarr/bin/ffprobe --strmprobe-version

# One-shot health check (wrapper active? backup present? ffprobe-full present?)
scripts/health-check.sh sonarr

# Manual probe of a .strm
docker exec sonarr /app/sonarr/bin/ffprobe \
    -v error -print_format json -show_format \
    "/movies/Example Movie/Example Movie (2024).strm"
```

Then import a `.strm` in the UI and confirm codec/resolution/duration/audio show
up, and that the `VideoFileInfoReader` error is gone from `/config/logs/<app>.txt`.

## Updating

**Docker mod** — pull the latest mod image and recreate the container:

```bash
docker pull ghcr.io/cosmicflow2512/strmprobe-mod:latest
docker compose up -d --force-recreate sonarr
```

If you pinned a release tag (`:vX.Y.Z`), bump the tag in your compose file
before recreating. The LSIO base image re-extracts the mod on every start, so
no further action is needed.

**Manual install** — refresh the wrapper source (git pull or download a new
release), then:

```bash
cp src/ffprobe-wrapper.sh /srv/sonarr/strmprobe/ffprobe-wrapper.sh
docker restart sonarr
```

The init script detects the new version on the next boot and re-installs it. (If
you mount the wrapper directly from the repo, just `git pull` and restart.)

## Rollback

**Docker mod:** remove the `DOCKER_MODS` entry (or just the `strmprobe-mod` part)
from the container's environment and recreate it — the next start uses the
image's pristine `ffprobe` and STRMProbe is gone.

**Manual install:** remove the init script and restore the original binary:

```bash
# In the container: restore the original binary
docker exec sonarr mv /app/sonarr/bin/ffprobe.real /app/sonarr/bin/ffprobe

# On the host: remove the init script from wherever you mounted it
# (the host path you mapped to /custom-cont-init.d in the container).
# Example for a typical Unraid layout:
rm /srv/sonarr-init/99-strmprobe

docker restart sonarr
```

## Bandwidth & load

Probing a URL means `ffprobe-full` downloads enough of the remote file to read the
container header/index — typically a few MB, up to ~50 MB for large MKVs with
trailing indexes. A full library re-probe can therefore pull **several GB** through
your remote source (NzbDAV, Xtream, …). Best practices:

- Avoid forcing a full library re-probe unless necessary.
- If your source has rate limits (e.g. NzbDAV download keys, Usenet retention),
  batch the work over time.
- Schedule intensive operations during off-peak hours.
- Enable the **result cache** below so repeat probes don't re-download.

## Result cache (optional)

Set `STRMPROBE_CACHE_DIR` to a writable path to cache probe results and skip the
repeat HTTP downloads described above — handy for large libraries and frequent
re-scans:

```yaml
environment:
  - STRMPROBE_CACHE_DIR=/config/strmprobe-cache
```

- **What's cached:** only **successful** `.strm` probes. A failed probe (e.g. an
  expired token) is never cached, so it's retried next time.
- **Cache key:** a hash of the `.strm` **contents** (the URL) **and** the ffprobe
  arguments — so a changed URL re-probes automatically, and different probe types
  (`-show_streams` vs `-show_chapters`, …) never return each other's data.
- **Invalidation:** automatic when a `.strm`'s URL changes. Old entries are **not**
  auto-evicted — the cache grows over time. Prune it yourself when needed, e.g. via
  cron: `find /config/strmprobe-cache -name '*.json' -mtime +30 -delete`, or clear
  it with `rm -rf /config/strmprobe-cache/*`.
- **Scope:** only network (`.strm`) probes are cached; normal local files are never
  touched. With the cache off (default), the wrapper behaves exactly as before.

## Testing & development

```bash
shellcheck -x src/*.sh scripts/*.sh tests/run.sh tests/lib/*.sh tests/cases/*.sh
bash tests/run.sh
```

The suite stubs `ffprobe.real` / `ffprobe-full` with scripts that echo their
arguments, so it asserts routing, URL parsing, option injection and exit-code
propagation without any real ffprobe and without root.

## Known limitations

- **Auth-token expiry.** If the `.strm` URL embeds a time-limited token (e.g.
  NzbDAV `?downloadKey=…`), probing an expired token will fail. Re-import or
  regenerate the `.strm`.
- **Architecture must match.** `ffprobe-full` is arch-specific; an amd64 binary on
  an arm64 host gives `exec format error`. The fetch/init scripts auto-detect
  amd64/arm64.
- **CLI-call assumption.** The wrapper works because the apps invoke `ffprobe` as a
  subprocess. If a future version embeds ffprobe as a library, the wrapper won't
  apply.
- **Maintenance.** Static `ffprobe-full` builds don't auto-update; refresh the
  binary if an FFmpeg HTTP-stack vulnerability matters to you.
- **Deferred features:** custom auth headers (`STRMPROBE_HEADERS`) and `rtmp`/`rtsp`
  schemes are not yet implemented. The code leaves room for these.

## License & the `ffprobe-full` binary

STRMProbe is licensed under **GPL-3.0** (see [`LICENSE`](LICENSE)).

The `ffprobe-full` binary is **not** distributed in this repository. It is
downloaded at deploy time by `scripts/fetch-ffprobe-full.sh` (or the init script)
from third-party static-build providers:

- [John Van Sickle](https://johnvansickle.com/ffmpeg/) — GPL build
- [BtbN](https://github.com/BtbN/FFmpeg-Builds/releases) — LGPL and GPL builds

Both are GPL-compliant for this use (ffprobe is invoked as a subprocess). Note the
John Van Sickle builds omit NVENC and FDK-AAC — irrelevant for probing; don't use
`ffprobe-full` for transcoding.

## Credits

Inspired by [JellySTRMprobe](https://github.com/firestaerter3/JellySTRMprobe), the
equivalent idea for Jellyfin. Built around the static FFmpeg builds from John Van
Sickle and BtbN.

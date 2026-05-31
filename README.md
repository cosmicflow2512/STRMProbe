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

## Repository layout

| Path | Purpose |
|---|---|
| `src/ffprobe-wrapper.sh` | the wrapper that replaces `/app/<app>/bin/ffprobe` |
| `src/strmprobe-init.sh` | `custom-cont-init.d` script: auto-detect apps, back up, install, auto-download |
| `scripts/fetch-ffprobe-full.sh` | standalone helper to download + verify `ffprobe-full` (host use) |
| `scripts/health-check.sh` | check a running container is correctly patched |
| `tests/` | self-contained bash test suite (no real binaries needed) |
| `examples/` | docker-compose examples + Unraid notes |

## Installation

You need three things reachable inside the container's `/config`:

1. `src/strmprobe-init.sh` → `/config/custom-cont-init.d/99-strmprobe`
2. `src/ffprobe-wrapper.sh` → `/config/strmprobe/ffprobe-wrapper.sh`
3. *(optional)* a pre-seeded `ffprobe-full` → `/config/bin/ffprobe-full`
   (otherwise auto-downloaded on first start — needs container network access)

See [`examples/docker-compose.sonarr.yml`](examples/docker-compose.sonarr.yml)
and [`examples/unraid-notes.md`](examples/unraid-notes.md) for concrete wiring.

After mounting/copying, restart the container. The init script runs as root before
the app, backs up the original `ffprobe` to `ffprobe.real`, installs the wrapper,
and prints a summary you can see with `docker logs <app> | grep STRMProbe`.

> **Installation order matters.** Name the init script with a high number
> (`99-strmprobe`). LSIO runs `custom-cont-init.d` scripts in alphabetical order,
> so a high number ensures STRMProbe runs **after** other mods that might also
> modify `/app/*/bin/`. A low number risks your wrapper being overwritten by a
> later-running mod.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `STRMPROBE_LOG` | `0` | `1` enables the wrapper debug log |
| `STRMPROBE_LOGFILE` | `/config/logs/ffprobe-wrapper.log` | log destination |
| `STRMPROBE_LOG_MAX` | `1048576` | log size cap in bytes (truncates in place) |
| `STRMPROBE_FULL` | `/config/bin/ffprobe-full` | path to the network-capable ffprobe |
| `STRMPROBE_REAL` | `<bindir>/ffprobe.real` | path to the original ffprobe |
| `STRMPROBE_WRAPPER_SRC` | `/config/strmprobe/ffprobe-wrapper.sh` | wrapper source the init script installs |

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

```bash
# Refresh the wrapper source (git pull or download a new release), then:
cp src/ffprobe-wrapper.sh /srv/sonarr/strmprobe/ffprobe-wrapper.sh
docker restart sonarr
```

The init script detects the new version on the next boot and re-installs it. (If
you mount the wrapper directly from the repo, just `git pull` and restart.)

## Rollback

```bash
# In the container: restore the original binary
docker exec sonarr mv /app/sonarr/bin/ffprobe.real /app/sonarr/bin/ffprobe

# On the host: remove the init script so it isn't re-installed
rm /srv/sonarr/custom-cont-init.d/99-strmprobe

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
- **Deferred features (not in v1.0):** a result cache (`STRMPROBE_CACHE_DIR`),
  custom auth headers (`STRMPROBE_HEADERS`), and `rtmp`/`rtsp` schemes. The code
  leaves room for these.

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

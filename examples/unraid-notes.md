# Unraid setup notes

> **Easiest path: the Docker mod.** Edit the container in the Unraid template, add
> a Variable `DOCKER_MODS` = `ghcr.io/cosmicflow2512/strmprobe-mod:latest` (pin a
> `:vX.Y.Z` tag in production), apply, and you're done — no appdata copying. The
> steps below are the manual (non-mod) alternative.

On Unraid the LinuxServer.io Sonarr/Radarr containers store their `/config` under
`/srv/<app>/`. For the manual setup,
the wrapper and (optional) `ffprobe-full` live under `/config`, but the **init
script must go at the container root `/custom-cont-init.d`** (LSIO does not run
custom scripts mounted inside `/config`), so it needs its own host directory.

## 1. Copy the artifacts into appdata

From a clone of this repo on the Unraid host:

```bash
APP=sonarr                               # or radarr
DEST=/srv/$APP             # mounted to /config in the container
INIT=/srv/$APP-init        # mounted to /custom-cont-init.d (NOT under /config)

# Init script -> a host dir you map to /custom-cont-init.d (must be root:root + executable).
mkdir -p "$INIT"
cp src/strmprobe-init.sh "$INIT/99-strmprobe"
chown root:root "$INIT/99-strmprobe"
chmod 755 "$INIT/99-strmprobe"

# Wrapper (and optional binary) live under /config.
mkdir -p "$DEST/strmprobe" "$DEST/bin"
cp src/ffprobe-wrapper.sh "$DEST/strmprobe/ffprobe-wrapper.sh"
chmod 755 "$DEST/strmprobe/ffprobe-wrapper.sh"

# Optional: pre-seed the binary so the container doesn't download it on first start.
# (Otherwise the init script auto-downloads it — needs container network access.)
bash scripts/fetch-ffprobe-full.sh "$DEST/bin/ffprobe-full"
```

Then add a Path mapping in the Unraid Docker template: Container Path
`/custom-cont-init.d` → Host Path `/srv/<app>-init`.

> The init script is named `99-strmprobe` (high number) on purpose: LSIO runs
> `custom-cont-init.d` scripts in alphabetical order, and a high number ensures
> STRMProbe runs **after** any other mod that might touch `/app/*/bin/`.

## 2. (Alternative) Use the Docker template "Path" mappings

If you prefer mounts over copying, add these container Path mappings in the
Unraid Docker template (Container Path : Host Path, read-only). The init-script
file on the host must be `root:root` and executable, or LSIO will ignore it:

| Container Path | Host Path | Mode |
|---|---|---|
| `/custom-cont-init.d/99-strmprobe` | `…/STRMProbe/src/strmprobe-init.sh` | ro |
| `/config/strmprobe/ffprobe-wrapper.sh` | `…/STRMProbe/src/ffprobe-wrapper.sh` | ro |
| `/config/bin/ffprobe-full` (optional) | `…/STRMProbe/bin/ffprobe-full` | ro |

Optionally add a Variable `STRMPROBE_LOG=1` to enable the debug log.

## 3. Restart and verify

```bash
docker restart sonarr   # or radarr
docker logs sonarr 2>&1 | grep STRMProbe          # init summary lines
docker exec sonarr /app/sonarr/bin/ffprobe --strmprobe-version
```

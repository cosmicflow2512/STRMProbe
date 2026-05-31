# Unraid setup notes

> **Easiest path: the Docker mod.** Edit the container in the Unraid template, add
> a Variable `DOCKER_MODS` = `ghcr.io/cosmicflow2512/strmprobe-mod:latest` (pin a
> `:vX.Y.Z` tag in production), apply, and you're done — no appdata copying. The
> steps below are the manual (non-mod) alternative.

On Unraid the LinuxServer.io Sonarr/Radarr containers store their `/config` under
`/srv/<app>/`. For the manual setup,
STRMProbe needs the init script, the wrapper, and (optionally) the static
`ffprobe-full` reachable inside `/config`.

## 1. Copy the artifacts into appdata

From a clone of this repo on the Unraid host:

```bash
APP=sonarr   # or radarr
DEST=/srv/$APP

mkdir -p "$DEST/custom-cont-init.d" "$DEST/strmprobe" "$DEST/bin"
cp src/strmprobe-init.sh   "$DEST/custom-cont-init.d/99-strmprobe"
cp src/ffprobe-wrapper.sh  "$DEST/strmprobe/ffprobe-wrapper.sh"
chmod +x "$DEST/custom-cont-init.d/99-strmprobe" "$DEST/strmprobe/ffprobe-wrapper.sh"

# Optional: pre-seed the binary so the container doesn't download it on first start.
# (Otherwise the init script auto-downloads it — needs container network access.)
bash scripts/fetch-ffprobe-full.sh "$DEST/bin/ffprobe-full"
```

> The init script is named `99-strmprobe` (high number) on purpose: LSIO runs
> `custom-cont-init.d` scripts in alphabetical order, and a high number ensures
> STRMProbe runs **after** any other mod that might touch `/app/*/bin/`.

## 2. (Alternative) Use the Docker template "Path" mappings

If you prefer mounts over copying, add these container Path mappings in the
Unraid Docker template (Container Path : Host Path, read-only):

| Container Path | Host Path | Mode |
|---|---|---|
| `/config/custom-cont-init.d/99-strmprobe` | `…/STRMProbe/src/strmprobe-init.sh` | ro |
| `/config/strmprobe/ffprobe-wrapper.sh` | `…/STRMProbe/src/ffprobe-wrapper.sh` | ro |
| `/config/bin/ffprobe-full` (optional) | `…/STRMProbe/bin/ffprobe-full` | ro |

Optionally add a Variable `STRMPROBE_LOG=1` to enable the debug log.

## 3. Restart and verify

```bash
docker restart sonarr   # or radarr
docker logs sonarr 2>&1 | grep STRMProbe          # init summary lines
docker exec sonarr /app/sonarr/bin/ffprobe --strmprobe-version
```

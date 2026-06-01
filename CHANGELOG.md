# Changelog

All notable changes to STRMProbe are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project follows
[Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-06-01

### Added
- Probe-tuning env vars `STRMPROBE_PROBESIZE` and `STRMPROBE_ANALYZEDURATION`, plus a
  network read/write timeout `STRMPROBE_RW_TIMEOUT` (default 30 s, `0` disables) so a
  dead/slow URL can no longer hang a probe and block an import.
- CI workflow (`.github/workflows/ci.yml`) running shellcheck + the test suite on pull
  requests and pushes.
- Semver release images: pushing a `vX.Y.Z` tag publishes `:vX.Y.Z` and `:vX.Y` GHCR
  images via `docker/metadata-action`.

### Changed
- Cache key now also includes the effective probe-tuning params.
- Bumped `actions/checkout` to v5 in both workflows (clears the Node 20 deprecation warning).

### Migration notes
- The cache-key change means cache entries created by v1.1.0 no longer match after the
  upgrade: the next library scan re-probes every `.strm` once, and old entries linger
  until removed. This is intentional. Clear stale files with
  `rm -f "$STRMPROBE_CACHE_DIR"/*.json`.

## [1.1.0] - 2026-06-01

### Added
- Optional on-disk result cache (`STRMPROBE_CACHE_DIR`): caches successful `.strm` probe
  results to skip repeat HTTP downloads on library re-scans.

## [1.0.0] - 2026-05-31

### Added
- Initial release: an `ffprobe` wrapper that lets Sonarr/Radarr (and Lidarr/Bazarr/
  Whisparr/Readarr) read media info from `.strm` files in LinuxServer.io containers.
- Auto-detecting `custom-cont-init.d` install script — patches every `/app/*/bin/ffprobe`,
  marker-based backup that survives image updates, auto-downloads `ffprobe-full`.
- Standalone `scripts/fetch-ffprobe-full.sh` (arch-aware download + protocol verify) and
  `scripts/health-check.sh`.
- LinuxServer.io Docker mod packaging — one-line install via
  `DOCKER_MODS=ghcr.io/cosmicflow2512/strmprobe-mod:latest`.
- Self-contained bash test suite; GPL-3.0 license.

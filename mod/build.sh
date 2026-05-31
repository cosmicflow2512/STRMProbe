#!/usr/bin/env bash
# Build the STRMProbe Docker mod image locally (single-arch, for testing).
# CI builds + pushes multi-arch via .github/workflows/build-mod.yml.
#
# Usage: bash mod/build.sh [tag]   (default tag: strmprobe-mod:test)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:-strmprobe-mod:test}"

bash "$HERE/stage.sh"
docker build -t "$TAG" "$HERE"
echo "Built $TAG"

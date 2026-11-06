#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker build -t english-trainer-quality -f Dockerfile.quality .
docker run --rm --user "$(id -u):$(id -g)" --mount "type=bind,src=$PWD,dst=/workspace,readonly" \
  -e HOME=/tmp english-trainer-quality

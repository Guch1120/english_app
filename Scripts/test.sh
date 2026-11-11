#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/ci/docker-build.sh -t english-trainer-dev .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/workspace" -w /workspace english-trainer-dev swift test --package-path Packages/VoiceLearning "$@"

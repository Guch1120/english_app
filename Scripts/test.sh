#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker build -t english-trainer-dev .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/workspace" -w /workspace english-trainer-dev swift test --package-path Packages/VoiceLearning "$@"

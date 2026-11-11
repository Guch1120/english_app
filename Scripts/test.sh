#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build on the host network: the default build network on CI runners has failed DNS resolution.
docker build --network=host -t english-trainer-dev .
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/workspace" -w /workspace english-trainer-dev swift test --package-path Packages/VoiceLearning "$@"

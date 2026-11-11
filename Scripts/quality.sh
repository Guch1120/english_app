#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/ci/docker-build.sh -t english-trainer-quality -f Dockerfile.quality .
git_mount=()
# A linked worktree's .git file points into the common Git directory by its host
# path. Mount that metadata read-only at the same path so git-based checks work
# from isolated /tmp worktrees as well as from the primary checkout.
if [ -f .git ]; then
  git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
  git_mount+=(--mount "type=bind,src=$git_common_dir,dst=$git_common_dir,readonly")
fi
docker run --rm --user "$(id -u):$(id -g)" --mount "type=bind,src=$PWD,dst=/workspace,readonly" "${git_mount[@]}" \
  -e HOME=/tmp english-trainer-quality

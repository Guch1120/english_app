#!/usr/bin/env bash
set -euo pipefail

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

for attempt in 1 2 3; do
  : > "$log_file"
  set +e
  swift test --package-path Packages/VoiceLearning 2>&1 | tee "$log_file"
  test_status=${PIPESTATUS[0]}
  set -e

  if [[ "$test_status" -eq 0 ]]; then
    exit 0
  fi
  if ! grep -Eiq 'badResponseStatusCode\((429|5[0-9]{2})\)|downloadError\(".*(server|connect|connection|network|timed out|timeout|temporarily unavailable).*"\)' "$log_file"; then
    exit "$test_status"
  fi
  if [[ "$attempt" -eq 3 ]]; then
    echo "SwiftPM binary artifact download failed due to a transient network response after ${attempt} attempts." >&2
    exit "$test_status"
  fi

  delay=$((attempt * 30))
  echo "SwiftPM binary artifact download hit a transient network error; retrying in ${delay}s (attempt $((attempt + 1))/3)." >&2
  sleep "$delay"
done

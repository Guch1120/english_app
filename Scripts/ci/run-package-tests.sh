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
  if ! grep -Fq 'badResponseStatusCode(504)' "$log_file"; then
    exit "$test_status"
  fi
  if [[ "$attempt" -eq 3 ]]; then
    echo "SwiftPM binary artifact download failed with HTTP 504 after ${attempt} attempts." >&2
    exit "$test_status"
  fi

  delay=$((attempt * 30))
  echo "SwiftPM binary artifact download returned HTTP 504; retrying in ${delay}s (attempt $((attempt + 1))/3)." >&2
  sleep "$delay"
done

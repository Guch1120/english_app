#!/usr/bin/env bash
set -euo pipefail
# The mount is read-only and user-owned; trust only this explicit checkout for git inspection.
git config --global --add safe.directory /workspace
# Also include scripts newly added in the current working tree during local verification.
mapfile -d '' shell_files < <(find Scripts -type f -name '*.sh' -print0)
shellcheck --external-sources "${shell_files[@]}"
actionlint -color -shellcheck=shellcheck
python3 -m unittest discover -s Scripts/ci -p 'test_*.py'
python3 Scripts/ci/policy.py
python3 Scripts/ci/vendor.py
# Redact findings rather than printing discovered credentials in public CI logs.
gitleaks git --no-banner --redact=100 --log-level warn .
printf 'PASS: shellcheck, actionlint, policy tests, CI policy, redacted Git history scan\n'

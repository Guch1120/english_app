# Automated PR checks

Every PR runs the `Validate` workflow without signing secrets. No automatic approval or merge is enabled. The stable `review-gate` status summarizes and requires the applicable checks:

| Check | What it checks |
|---|---|
| ShellCheck | Shell syntax and common argument/error-handling mistakes |
| actionlint 1.7.12 | GitHub Actions expressions, job references and embedded shell |
| Gitleaks 8.30.1 | Committed Git history for recognized credential patterns, with values redacted in logs |
| CI policy + negative tests | Full-SHA action pins; read-only token permissions; no PR secret references or deployment environment; manual-only/main-only deployment jobs; no tracked signing/credential files |
| Swift tests | Learning, persistence, alignment and coordinator behavior covered by tests |
| macOS/Xcode | Simulator build/analyze and unsigned device archive/icon validation |

Documentation-only or USB-tool-only PRs still get all quality/security checks but skip Swift/macOS builds. App/package/Xcode project changes, build scripts or any workflow require the full build path. Workflow dispatch runs all build checks. `review-gate` fails if a required check fails, is cancelled or unexpectedly skips; a skipped build passes only when change selection explicitly says it was unnecessary.

Run local quality checks in Docker:

```bash
bash Scripts/quality.sh
```

The tools use a pinned Swift image; release binaries are pinned to versions and verified against checked-in SHA-256 values. These are development CLI tools, not linked app dependencies. actionlint and Gitleaks are MIT-licensed; ShellCheck is GPL-3.0; the Ubuntu packages retain their distribution license notices inside the container.

## What the result means

A green gate establishes only the checks listed above. It does not prove generated-content correctness, external SDK/model compatibility, model accuracy, memory limits, audio quality, real-device UX or signing/API permission. There is no automatic natural-language/AI code reviewer in this workflow. Changes to CI/policies and dependencies, data deletion/migration, permissions and external communication still need a focused review of their intent and risks. PR descriptions should provide the problem, resulting behavior, evidence and remaining limitations, so users do not have to inspect every implementation line to understand the decision.

A credential finding is redacted in CI but detecting a credential after a public push cannot undo exposure; the affected key must be revoked. No scanner can recognize every possible credential.

## Requiring the gate before merge

In GitHub Settings → Rules → Rulesets, add `review-gate` as a required status check for main and keep changes routed through PRs. If an existing rule requires the old `core` or `ios` status, replace those required contexts with `review-gate`, because legitimate docs-only changes skip them. Preserve other repository protections. This PR does not edit repository rules or enable auto-merge.

## Deployment result recorded 2026-11-06

[TestFlight workflow run 42211956318](https://github.com/Guch1120/english_app/actions/runs/42211956318) completed successfully after PR #3 merged. This confirms the upload command completed, not Apple's subsequent processing, internal-group assignment or installation through TestFlight.

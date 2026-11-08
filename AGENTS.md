# Development rules

- Run local compilers, package managers, and tests in Docker (`bash Scripts/test.sh`). Do not install SDKs on the host.
- iOS build and UI validation run on GitHub Actions macOS. Linux tests do not establish iOS build success.
- Work on `codex/` feature branches and merge through reviewed PRs. Never push directly to main.
- Keep learning logic independent of inference SDKs and UI. Put reusable libraries in Packages.
- No cloud inference, no user-content logging, no secrets or model binaries in Git.
- Unimplemented or unverified engines must remain clearly labeled and unavailable for real inference.
- Do not modify the reference project. Verify model APIs and licenses before adding dependencies.
- Before opening a PR, run `bash Scripts/quality.sh` in addition to checks relevant to the change. Review the diff for behavior/security risks and report concrete validation plus remaining uncertainty. A green automated gate is not a claim of full semantic or real-device correctness.
- Summarize each PR for the user: problem, resulting behavior, verification and material risks. Do not require the user to inspect every source line; highlight the decisions and high-impact changes that need attention.
- At each development milestone, update Docs with implemented behavior, validation evidence, remaining uncertainty, and concrete next steps for handoff.

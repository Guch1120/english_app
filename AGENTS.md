# Development rules

- Run local compilers, package managers, and tests in Docker (`bash Scripts/test.sh`). Do not install SDKs on the host.
- iOS build and UI validation run on GitHub Actions macOS. Linux tests do not establish iOS build success.
- Work on `codex/` feature branches and merge through reviewed PRs. Never push directly to main.
- Keep learning logic independent of inference SDKs and UI. Put reusable libraries in Packages.
- No cloud inference, no user-content logging, no secrets or model binaries in Git.
- Unimplemented or unverified engines must remain clearly labeled and unavailable for real inference.
- Do not modify the reference project. Verify model APIs and licenses before adding dependencies.

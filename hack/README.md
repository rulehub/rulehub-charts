# hack/

Developer scripts for generation, verification, tooling, release, and tests.

## Layout

- gen/ — generators and content builders (manifest, tables, policies, snapshots)
- verify/ — governance, determinism, integrity, size, drift, schema checks
- tools/ — diffing, analysis, helpers (schema coverage, semver, reports)
- release/ — packaging, signing/attestations, publishing helpers
- test/ — fuzzing, smoke tests, profile matrix
- ci/ — CI-only helpers and composite steps
- drift/ — drift comparison helpers

## Entrypoints

Top-level wrappers under `hack/*.sh` have been removed to reduce noise. Always invoke scripts from their canonical subfolders, for example:

- `bash hack/gen/gen-manifest.sh`
- `bash hack/verify/verify-size.sh`
- `bash hack/tools/template-diff.sh`
- `bash hack/release/publish-release-artifacts.sh`
- `bash hack/test/kind-smoke.sh`

If you had any local aliases pointing to legacy paths, update them to the subfolder variants.

## Conventions

- All scripts are bash with `#!/usr/bin/env bash` and `set -euo pipefail`.
- No secrets in code; use environment variables or CI OIDC where needed.
- Keep outputs deterministic (no timestamps/randomness by default).
- Sort inputs before emitting content; keep diffs small and stable.

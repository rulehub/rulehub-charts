# hack/test

Lightweight test helpers and smoke tests:
- `fuzz-policies.sh`: randomized enable/disable runs to catch template issues
- `kind-smoke.sh`: ephemeral kind cluster install/uninstall smoke test
- `test-profile-matrix.sh`: render counts across profile scenarios

Back-compat: Top-level `hack/*.sh` wrappers exec the implementations here.
# hack/test

Local smoke tests and harnesses:
- fuzzing policies and performance harnesses
- kind-based smoke tests
- profile matrix quick checks

Invoking via the legacy paths under `hack/*.sh` still works; they call into this folder.

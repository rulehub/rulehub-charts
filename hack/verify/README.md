# hack/verify

Verification and governance checks used in CI and local validation:
- schema, rendering, and determinism gates
- integrity, id alignment, and annotation checks
- performance, size, deprecation lifecycle, and policy sync

Back-compat note: Original `hack/verify-*.sh` files at the repo root are wrappers that exec these implementations.# hack/verify

Verification and governance checks executed locally and in CI:
- determinism, integrity, size and performance gates
- schema and annotation validation
- drift, freeze and deprecation windows

Original top-level `hack/*.sh` commands remain as wrappers pointing here to preserve compatibility.

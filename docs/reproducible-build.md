# Reproducible Build Factors

This chart aims for deterministic (reproducible) builds so that the exact same
inputs produce identical packaged artifacts and `helm template` output.

## Factors & Controls

| Factor | Risk | Mitigation / Current Control |
|--------|------|------------------------------|
| Helm version drift | Different YAML rendering or ordering | Pin a minimum Helm version in CI (document; future: `hack/verify-helm-version.sh`). `reproducible-build-check.sh` outputs the active version for audit. |
| Non-deterministic timestamps | `build.timestamp` would differ per run | Default `values.yaml` leaves `build.timestamp` empty. Verification script can be extended to fail if non-empty during deterministic mode. |
| File ordering (glob) | Random order produces different concatenation | All loops explicitly sort via Helm's deterministic `.Files.Glob` enumeration; integrity aggregation sorts paths using `find ... \| sort`. |
| Random / generated names | Hash / UUID names change | No random names used in templates. Helpers derive names from filenames or annotations. |
| Placeholder policy inclusion variability | Different sets change integrity hash | Placeholders excluded by default for provenance unless `--include-placeholders` flag passed. Pre-pack hook removes them (`hack/prepack-remove-placeholders.sh`). |
| Floating external dependencies | Upstream changes alter outputs | No external network fetch performed during render. All content vendored in `files/`. |
| Unstable whitespace or map key order | Diff noise, hash changes | YAML emitted via Helm `toYaml` on parsed objects; Go template map iteration is stable for constructed maps here (Helm's `toYaml` preserves key insertion order; we build maps deterministically). |
| Git dirty working tree | Uncommitted changes not tracked | Provenance captures `workspaceState` (`dirty` if diffs present). |
| Integrity hash variability | Input ordering differences | `aggregate-integrity.sh` sorts file list before concatenation; identical content => identical hash. |

## Verification Steps

1. Deterministic template: `make verify-deterministic` → reports `Determinism OK`.
2. All rendered resources labeled: `make labels-verify`.
3. Repro build heuristic: `bash hack/reproducible-build-check.sh`.
4. (Optional) Package diff across two runs: automatically done inside reproducible build check.

## Developer Guidance

- Do not add timestamps, UUIDs, or random numbers inside templates unless
  guarded by an explicit opt-in value that defaults to empty / disabled.
- When adding new file iteration logic, ensure a sorted order (e.g. rely on
  `.Files.Glob` and avoid range over a map unless keys are first sorted).
- Keep `build.timestamp` empty for CI deterministic verification runs; allow
  users to set it only when they need traceability over reproducibility.

## Future Enhancements

- Add a `hack/verify-helm-version.sh` that enforces an allowed version set.
- Extend provenance to include the integrity hash of `Chart.yaml` itself and
  template helper checksums.
- Provide a `SOURCE_DATE_EPOCH` based timestamp normalization (optional mode).

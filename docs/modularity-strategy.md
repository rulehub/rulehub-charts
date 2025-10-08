# Chart Modularity & Size Strategy

## Current Size Snapshot
(Approximate due to collection interruptions; refine via scripted task later)
- Total policy YAML files: ~435
- Kyverno: ~145 files (~88 KB)
- Gatekeeper Constraints: ~145 files (~46 KB)
- Gatekeeper ConstraintTemplates: ~145 files (~127 KB)
- Aggregate size: ~255–260 KB (policy sources only)
- File size distribution (rough buckets):
  - <=2KB: majority (compact validation rules)
  - 2–5KB: moderate subset
  - 5–10KB: fewer complex policies
  - >10KB: handful of largest templates (optimize / split potential)

## Observations
1. Symmetry: Equal count across the three directories suggests generator parity; enables bundle splitting.
2. Largest weight sits in ConstraintTemplates (logic bodies + schemas) — prime target for optionalization.
3. Aggregate size is near a 250 KB soft threshold; future growth risks bloat (Helm chart fetch & review overhead).
4. Many small files => high inode / render overhead; grouping may reduce cognitive load (profiles).

## Modularity Goals
- Reduce default install surface area for fast trials (baseline < 100 policies, <120 KB).
- Provide progressive bundles for stricter compliance use cases.
- Allow selective enablement via high‑level profile keys while keeping per‑policy toggles.

## Proposed Bundling Model
| Bundle | Contents | Criteria | Default? |
|--------|----------|----------|----------|
| baseline | Core safety + low false positive | Low risk, widely applicable | Yes |
| compliance | Regulatory (betting, finance, etc.) | Domain/regulation tagged | No |
| strict | Adds high enforcement / disruptive rules | validationFailureAction=enforce candidates | No |
| extended | Heavy / large templates, niche patterns | Size >5KB or rare labels | No |
| experimental | New / recently added / unstable | Introduced <2 minors ago | No |

## Values Structure Extension
```yaml
profiles:
  enabled: [baseline]  # ordered merge
  # explicit opt-ins: compliance, strict, extended, experimental
policy:
  # existing fine-grained switches stay intact
```
Resolution order:
1. Start with disabled for all policies.
2. Merge each profile in `profiles.enabled` sequence (true wins unless explicitly false later).
3. Apply explicit user overrides under `policy:`.
4. Emit annotation `rulehub.profile.applied: <list>` for traceability.

## Profile Mapping Manifest
Introduce `profiles.yaml` (generated) with structure:
```yaml
baseline:
  - pod-security-baseline-policy
  - image-tag-immutable-policy
strict:
  - host-network-block-policy
  - privileged-block-policy
extended:
  - large-constrainttemplate-x
```
Generator derives membership by rules:
- baseline: tag `tier=baseline` & not large & not high_risk.
- strict: label `risk=high` OR enforce-only.
- extended: size >5KB OR label `complexity=high`.
- compliance: annotation `regulatory/*` present.
- experimental: annotation `introducedVersion: > (chartVersion - 2 minors)`.

## Implementation Steps
1. Generator Enhancement: produce `profiles.yaml` + inject size/risk labels (size bucket computed at generation time).
2. Values Schema: add `profiles.enabled` array enum referencing available profile names.
3. Template Logic: In `_helpers.tpl`, define function `includePolicy` performing profile merge + explicit toggle check.
4. Backward Compatibility: If `profiles.enabled` absent, assume `[baseline]` for new installs; older toggles unaffected.
5. Docs: README section describing profiles & override examples.
6. Tests: ct tests per profile matrix (baseline, kyverno-only, gatekeeper-only, strict combo).

## Optimization Opportunities
- Deduplicate large shared schema fragments via `{{- define }}` blocks in templates (especially for repeated Rego libs).
- Consider moving experimental & extended bundles to optional subcharts (`rulehub-policies-extras`) if size >400 KB.
- Pre-render heavy templates to reduce Helm rendering time (cache integrity hash to detect changes).

## Future Metrics
Add `hack/size-report.sh` to emit JSON:
```json
{ "files": 435, "bytes": 261236, "buckets": {"<=2K":320,"2-5K":70,"5-10K":30,">10K":15} }
```
Fail CI if:
- Total bytes > 400000 (warn at 300000)
- Any single file > 30KB (flag for refactor)

## Risk Considerations
- Profile misclassification => missing protections: mitigate with explicit test ensuring key critical policies always in baseline.
- Drift between `profiles.yaml` and annotated size/risk labels: verify in `verify-policies-sync.sh`.

## Quick Win Checklist
- [ ] Add size labeling script.
- [ ] Generate `profiles.yaml` prototype.
- [ ] Implement helper `includePolicy`.
- [ ] Extend `values.schema.json`.
- [ ] Add README profiles section.
- [ ] Add ct matrix for profiles.

---
Generated strategy document; adjust metrics script to solidify approximate numbers.

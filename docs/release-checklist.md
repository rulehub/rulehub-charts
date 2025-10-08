# Release Checklist (RuleHub Policy Sets Chart)

Use this checklist for every release. Automate sequentially; keep manual notes for gaps.

## Pre-flight

- [ ] Confirm working tree clean (`git status`)
- [ ] Fetch & rebase onto main (`git pull --rebase`)
- [ ] Verify no unmerged PRs tagged `release-blocker`
- [ ] Decide SemVer bump (see Decision section below)
- [ ] Ensure CI image tag is pinned (repo variable `CI_IMAGE_TAG` or workflow input `ci_image_tag`) to avoid `latest` drift in CI and local act runs

## Version Bump

- [ ] Update `Chart.yaml` `version:` (SemVer) and `appVersion:` if meaningful
- [ ] Update any referenced version in `README.md` examples
- [ ] Run `./hack/version-check.sh` (should pass after edit)

## Policy Assets Regeneration

- [ ] (If sources changed) Run policy generation pipeline (`make generate-policies` or manual steps)
- [ ] (pre-release) Generated values/report tables are not maintained before the first public release; skip regenerating `VALUES_TABLE.md` for now.
- [ ] Run `hack/verify-values-table.sh` (should pass)
- [ ] Optional: regenerate manifest/integrity (future) `make manifest`

## Validation

- [ ] `helm lint .`
- [ ] `helm unittest -3 -f tests/*.yaml .`
- [ ] Render & kubeconform (baseline K8s versions):
  - [ ] `helm template rulehub-policies . > rendered.yaml`
  - [ ] `kubeconform -strict -ignore-missing-schemas rendered.yaml`
- [ ] ct lint (chart-testing): `ct lint --config ct-lint.yaml`
- [ ] Custom verify scripts:
  - [ ] `hack/verify-render.sh`
  - [ ] `hack/verify-id-name-alignment.sh`
  - [ ] `hack/verify-policies-sync.sh`
  - [ ] `hack/list-underscore-duplicates.sh` review deprecations

## Enforcement & Risk Review

- [ ] List policies with enforce (`grep -R "validationFailureAction: enforce" files/kyverno`)
- [ ] Confirm rationale comments present in `values.yaml` (future automation)

## Drift & Integrity

- [ ] (If index available) Drift check vs core `dist/index.json`
- [ ] Ensure no orphan keys (values vs files) – run sync script
- [ ] (Future) Integrity hash updated (manifest, aggregate)

## Security / Supply Chain

- [ ] (If enabled) Generate SBOM (`syft dir:. -o spdx-json=sbom.json`)
- [ ] (If enabled) Vulnerability scan (`grype sbom:sbom.json` – ensure policy thresholds)
- [ ] (If enabled) Prepare Cosign keys or keyless environment configured

## Packaging

- [ ] Package chart: `helm package .` (verify produced `rulehub-policies-X.Y.Z.tgz`)
- [ ] (If signing) `cosign sign oci://ghcr.io/rulehub/charts/rulehub-policies:X.Y.Z`
- [ ] (If attest) `cosign attest ...` (SBOM, provenance)

## Release Commit & Tag

- [ ] Commit changes: `git add . && git commit -m "chore(release): vX.Y.Z"`
- [ ] Tag: `git tag vX.Y.Z`
- [ ] Push: `git push && git push --tags`

## GitHub Release

- [ ] Draft release notes (CHANGELOG sections: Added/Changed/Removed/Security/Integrity).
- [ ] Attach / reference OCI URL: `oci://ghcr.io/rulehub/charts/rulehub-policies --version X.Y.Z`
- [ ] Include integrity hash (short) & SBOM link (if generated)

## Post-Release

- [ ] Create follow-up issue(s) for any deferred TODOs / deprecations
- [ ] Update roadmap if scope changed
- [ ] Optional: set/update repo variable `CI_IMAGE_TAG` to a released `ci-charts` tag for deterministic CI
- [ ] Announce (Slack / internal channel)

## Decision: SemVer Bump Guide

- MAJOR: Breaking value key removals, default enforcement escalations, structural template changes breaking consumers.
- MINOR: New policies (additive), new optional values, non-breaking enhancements.
- PATCH: Fixes to annotations, docs, metadata, non-behavioral template refactors.

## Fast Audit Commands (Reference)

```bash
# Changed policy files since last tag
git diff --name-only $(git describe --tags --abbrev=0)..HEAD -- files/ | grep -E '\\.(ya?ml)$'

# Orphan keys (simple heuristic)
comm -3 <(yq '.gatekeeper.policies | keys | .[]' values.yaml | sort) <(ls files/gatekeeper | sed 's/\\.ya\\?ml$//' | sort)

# Enforced policies list
grep -R "validationFailureAction: enforce" files/kyverno | cut -d: -f1 | sort -u
```

## Future Automation Placeholders

- Drift check GH Action status: PASS/FAIL link
- Integrity hash generation & verification step outputs
- Automatic CHANGELOG generation from conventional commits

---

Maintain this file as features mature; keep steps atomic and checkable.

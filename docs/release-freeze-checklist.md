# Release Freeze Checklist

This checklist is used once a release version is cut (e.g. tag candidate or branch) to enforce a *stability window* prior to publishing.

## 1. Preconditions

- [ ] Target version determined (Chart.yaml bumped appropriately)
- [ ] CHANGELOG draft section generated (make changelog-generate ...)
- [ ] SemVer suggestion reviewed (make semver-analyze)
- [ ] Deprecation window verification clean (make deprecation-verify OLD_VALUES=prev/values.yaml) — note: if this is the first public release, no deprecation window checks are required

## 2. Entering Freeze

- [ ] Announce freeze (issue / Slack) including allowed change scope
- [ ] Record freeze reference (git tag or commit): FRZ_REF=<sha>
- [ ] Create immutable artifact snapshot if desired (manifest.json, integrity hash)

## 3. Allowed Changes During Freeze

Only the following files (or subsets) may change without special override:

- CHANGELOG.md (current release section only)
- Chart.yaml (version line ONLY if further bump required)
- (pre-release) Generated values and risk tables are not maintained before the first public release; these steps can be skipped.
- manifest.json (if regeneration due to doc-only corrections; policy hashes unchanged)
- Top-level *.md documentation files (excluding files/ tree)

Optional (if explicitly allowed): non-render-impacting scripts in hack/ (verified with --allow-hack flag)

## 4. Disallowed (Require Critical Override)

- files/ (policy YAML content changes)
- templates/ (Helm logic)
- values.yaml / values.schema.json changes
- _helpers.tpl changes
- Addition/removal of policies (unless reverting a regression prior to GA)

## 5. Verification Commands

```bash
# Verify no disallowed changes since freeze reference
make freeze-verify REF=$FRZ_REF
# Allow hack script adjustments (non-render) if pre-approved
make freeze-verify REF=$FRZ_REF ALLOW_HACK=1
# Critical fix path (commit must include [critical-fix])
make freeze-verify REF=$FRZ_REF ALLOW_CRITICAL=1
```

## 6. Critical Fix Procedure

- [ ] Open issue labeled critical-fix describing root cause & impact
- [ ] Implement minimal change; commit message includes [critical-fix]
- [ ] Rerun full verification suite (make verify)
- [ ] Re-run freeze verification with --allow-critical

## 7. Exit Criteria

- [ ] All verify targets passing (labels, integrity, deterministic, performance)
- [ ] No freeze violations
- [ ] CHANGELOG finalized (Added/Changed/Removed/Security/Integrity)
- [ ] Tag created & signed (if signing configured)
- [ ] Artifacts published (OCI, SBOM, attestations)

## 8. Post-Release

- [ ] Update roadmap (mark completed items DONE)
- [ ] Open follow-up issues for deferred items
- [ ] Consider raising next development version

---
Generated & maintained with governance scripts. Update scope rules if release process evolves.

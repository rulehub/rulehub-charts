# Project Roadmap

Structured view of planned evolution. Buckets reflect intent rather than rigid timelines; items may shift based on user feedback, security findings, or ecosystem changes.

## Short-term (next 1–2 minor releases)

- Integrity / Supply Chain
  - Provenance & SBOM attestation automation (cosign `slsaprovenance`, SPDX) – automate via Make + CI.
  - Determinism gate finalized (double render hash compare in CI) – fail workflow on mismatch.
- Tooling Hardening
  - Kubeconform checksum verification script (`hack/verify-kubeconform-checksum.sh`) + `kubeconform-verify` make target.
  - `integrity-all` meta target (manifest + aggregate + verify + README badge check).
- Documentation & Governance
  - Normalization plan doc (`docs/normalization-plan.md`) & underscore → dash migration lifecycle references.
  - Security / SBOM & scan placeholder badges in `README.md` (non-blocking initially).
  - MIGRATION.md: pending dash normalization table population.
- Automation
  - Provenance generation script (`hack/generate-provenance.sh`).
  - Governance workflow (deprecation window, soft delete, underscore gate, freeze, size budget).
- Quality Gates
  - Performance baseline enforcement (no >20% regression in total rendered size / time).
  - Policy manifest drift surfaced earlier (pre-commit optional hook).

## Mid-term (2–4 minor releases)

- Release & Change Intelligence
  - Automated SemVer classification (manifest + schema diff heuristics).
  - CHANGELOG section generation from manifest + risk deltas.
  - Deprecation window automation (issue or PR comments when threshold reached).
- Profiles Evolution
  - Profile definitions (`profiles:` map) with inheritance & conflict detection tests.
  - Remote bundles index consumption (`values.policies.indexUrl`) + sha256 verification.
- Schema & Validation
  - Coverage metric (% of policies represented in schema / values).
  - Enforce enumerations for enforcement levels & profiles.* structure.
  - Schema versioning & compatibility rules.
- Developer Experience
  - Dev script validating only changed YAML (scoped lint / schema / id checks).
  - Pre-commit hook bundle (yaml lint, schema validate, id annotation check) published.
  - Golden snapshot hash tooling for rendered policies (per-file) with drift reporting.
- Observability & Metadata
  - Integrity ConfigMap export (optional flag) for in-cluster inspection.
  - Extended build annotations (timestamp, commit, integrity hash) in metadata.

## Long-term (strategic / major feature tracks)

- Profiles v2 with Kubernetes version gating & conditional inclusion.
- Remote policy set aggregation (consume multiple indices, merge & verify integrity).
- SBOM as separate OCI artifact (multi-arch / layered future images if introduced).
- Risk & Impact automation (derive risk table heuristics + coverage prioritization suggestions).
- License compliance pipeline (scan policy sources & templates for license metadata).
- Advanced release automation (tag signing, artifact promotion, freeze governance auto‑gates).
- CodeQL / Scorecard integration (pinned action SHAs, supply chain posture badges).
- Render caching & artifact reuse across multi-version matrix in CI to cut runtime.

## Completed (selected notable)

- Initial integrity aggregation & badge.
- Enforcement rationale documentation.
- Release & freeze checklists.
- Maintainers file and repository labeling taxonomy.

## Guiding Principles

- Deterministic outputs: identical inputs (policy sources + values) must produce identical packaged artifacts & hashes.
- Explicit integrity: every distributed unit is attestable (hash, signature, provenance).
- Progressive hardening: introduce gates in audit mode before enforcing fail states.
- Minimal cognitive load: documentation remains concise, auto-generated where practical.

## Feedback & Prioritization

Open issues or discussions to propose reprioritization. Short-term items may be swapped if a security or determinism concern surfaces.

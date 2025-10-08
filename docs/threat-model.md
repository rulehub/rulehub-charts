# Threat Model (Rulehub Charts Supply Chain)

## 1. Flow Overview (Data / Artifact Path)

Source (core rulehub metadata + policy templates) → Generation (local / CI scripts in `hack/`) → Policies in `files/` (Gatekeeper / Kyverno YAML) → Helm Chart (templating + values) → CI (lint, tests, signing, OCI publish) → Consumer Cluster (chart install, policies enforced).

Trust boundaries across transitions:
1. Core → Generation: ingest of external metadata/templates.
2. Generation → Git (PR): pre‑review artifacts (low trust) → post‑review (elevated trust).
3. Repository → CI: code + policies enter environment with secrets (signing, publish).
4. CI → OCI Registry: released chart / attestations / signatures.
5. Registry → Cluster: consumer selects version; verifies integrity & provenance.

## 2. Assets
- A1: Policy contents (`files/**/*.yaml`).
- A2: `rulehub.id` annotations (semantic binding ID ↔ resource name).
- A3: `values.yaml` (enable / enforcement configuration).
- A4: Helm chart (templates, `Chart.yaml`, SemVer version).
- A5: Generation / integration scripts (`hack/*.sh`).
- A6: Signed chart artifacts (OCI + cosign signatures, optional provenance / attestations).
- A7: Integrity data / manifest hashes (planned `manifest.json` or aggregate hash).
- A8: CI secrets (cosign private material / keyless OIDC tokens).
- A9: Git history (audit of changes & reviews).
- A10: Released immutable versions (tags, packages).

## 3. Actors
- AC1: Maintainers (full access / signing authority).
- AC2: Contributors (fork PR, limited rights).
- AC3: CI / automation (GitHub Actions runners).
- AC4: Registry consumer / cluster admin.
- AC5: External attacker (anonymous).
- AC6: Malicious insider (compromised maintainer account).

## 4. Trust Boundaries
| Boundary | Description | Risk |
|----------|-------------|------|
| TB1 | Core input → local generation | Metadata tampering |
| TB2 | Local generation → PR | Malicious policy injection pre‑review |
| TB3 | Repo → CI (Actions) | Supply chain (malicious workflow) |
| TB4 | CI → Registry | Artifact swap before signing |
| TB5 | Registry → Cluster | Replay / downgrade attack |
| TB6 | Chart install → Admission controllers | Incorrect enforcement impacts workloads |

## 5. STRIDE Threat Summary
| Category | Threat | Assets | Vector | Impact | Existing / Planned Mitigations |
|----------|--------|--------|--------|--------|--------------------------------|
| Spoofing | Commit author spoof | A9 | Stolen Git token | Untrusted code merged | Commit signing (GPG/Sigstore), branch protection, 2FA |
| Tampering | Policy modified post‑review | A1,A4 | Force-push / altered workflow artifact | Malicious code in clusters | No-force branch protection, action pin by SHA, `verify-integrity.sh` |
| Repudiation | Lack of generation traceability | A1-A5 | Missing provenance | Cannot prove origin | SLSA provenance (cosign attest), CI log retention |
| Information Disclosure | CI secret leak | A8 | Logs / echo | Signature compromise | Secret masking, least privilege, keyless OIDC |
| Denial of Service | Overly restrictive enforcement policy | A3,A6 | Malicious PR | Admission blockage | Review policy, selective enable tests, smoke tests |
| Elevation of Privilege | Weakening security via replaced Kyverno policy | A1,A3 | Subtle PR diff | Reduced protection | Semantic diff review, enforce list test, risk scoring |
| Tampering | Replay old chart (downgrade) | A6,A10 | Install outdated version | Reintroduced vulns | Enforce minimal version guidance, signature timestamp validation |
| Tampering | Modify `rulehub.id` annotation | A2 | Targeted change | Break traceability | ID ↔ filename check script, CI failure on mismatch |
| Tampering | Values/files drift | A1,A3 | Missing policy in chart | Inconsistent security posture | `verify-policies-sync.sh`, chart-testing |
| Information Disclosure | Extra debug data in artifact | A4 | Added sensitive paths | Potential infra leak | Review, lint deny debug annotations |

## 6. Detailed Threats & Mitigations
### 6.1 Policy Injection / Substitution
- Risk: Malicious policy blocks critical objects or weakens controls.
- Mitigations: Code review (≥2 approvals for critical), auto diff hash summary, integrity manifest.

### 6.2 Core ↔ Chart Drift
- Risk: Outdated or orphaned policies.
- Mitigations: Drift check (set of IDs), CI failure on divergence.

### 6.3 Non‑Deterministic Generation
- Risk: Non‑reproducible build → harder integrity verification.
- Mitigations: File sorting, stable YAML formatting (ordered keys), whitespace normalization.

### 6.4 Replay / Downgrade Attack
- Risk: Installation of unsupported older release.
- Mitigations: SECURITY.md with minimum supported; recommend automation to validate latest minor; transparency log timestamps.

### 6.5 In‑Workflow Substitution
- Risk: CI script mutates artifact after tests.
- Mitigations: Separate build / sign / publish stages; immutable build containers; pin actions by SHA.

### 6.6 Signing Key Compromise
- Risk: Attacker signs malicious chart.
- Mitigations: Keyless cosign (OIDC) + short-lived certs; rotation; minimal secret exposure.

### 6.7 Incorrect Enforcement (False Positive Lockout)
- Risk: Mass deployment failures.
- Mitigations: Default audit; staged escalation (audit → warn → enforce); single-policy enable test.

### 6.8 Manifest Integrity
- Risk: Undetected modification of single file.
- Mitigations: `verify-integrity.sh`, publish `manifest.json` (hash), aggregate hash annotated in release.

## 7. Threat → Control Coverage (Condensed)
| Threat | Core Controls | Enhancements |
|--------|---------------|--------------|
| Policy substitution | Review, integrity hash, drift-check | Semantic diff / policy AST lint |
| Chart replay | SemVer policy, signature verify | Policy gate minVersion |
| Key compromise | Keyless, OIDC attest | Hardware-backed key (Fulcio cert) |
| Values inconsistency | Sync scripts, CI test | Auto-fix PR bot |
| Enforcement error | Staged rollout, tests | Risk scoring + approval gate |
| Missing provenance | Cosign attest | SLSA v1.0 predicate |
| Annotation weakening | ID/name check | JSON Schema for annotations |

## 8. Roadmap Recommendations
1. Introduce `manifest.json` + aggregate integrity hash (SHA256 concat over sorted files).
2. Add SLSA provenance attestation (builder id, materials list).
3. Enforcement escalation workflow (issue template for promote → enforce).
4. Automatic risk score generator (resource type + enforcement).
5. Signed snapshot tests (hash rendered YAML) for early diff detection.
6. Action pinning by SHA + Renovate automation.
7. JSON Schema validation of annotations (rulehub.id regex: `^[a-z0-9]+(\.[a-z0-9_]+)*$`).
8. Determinism verification in CI (second run hash equality).

## 9. Residual Risks
- Maintainer insider threat (organizational separation of duties required beyond technical controls).
- Zero-day in helm/kyverno/gatekeeper leading to unintended effects (mitigated by timely updates + SBOM scanning).
- Consumer-side verification gaps (if signatures ignored) → needs documentation emphasis.

## 10. Summary
Current model relies on: (a) Git transparency, (b) baseline integrity via scripts, (c) planned cryptographic signing. Next critical steps: automate manifest hashing, provenance, and an enforcement level management process.

---
Update this document when generation logic, signing scheme, or supply chain stages change.

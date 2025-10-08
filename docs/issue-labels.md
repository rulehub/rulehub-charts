# Recommended GitHub Issue Labels

This label set is tuned for developing this Helm chart with Gatekeeper / Kyverno policies.

## Core types
- type/bug — Bug in templates, generation, or unexpected behavior.
- type/feature — New feature (script, automation, CI/CD infra).
- type/policy-add — Adding a new policy.
- type/policy-update — Modifying an existing policy (logic, annotations, enforce change).
- type/docs — Documentation / README / tables updates.
- type/refactor — Technical debt, template simplification.
- type/test — Adding or changing tests / snapshots / ct.
<!-- Deprecation-related labels are omitted until after the first public release. -->
- type/chore — Routines (deps, formatting, lint).

## Priorities
- priority/high — Needs quick action (production breakage, critical drift).
- priority/medium — Normal priority.
- priority/low — Can be deferred.

## Enforcement / Risk
- risk/high — Policy with enforce, may block deployments.
- risk/medium
- risk/low

## Release & SemVer
- semver/major — Breaking changes (removals, enforce behavior changes).
- semver/minor — New policies or new options.
- semver/patch — Fixes without behavior changes.

## Drift & Integrity
- drift — Divergence from core index.json or manifest.
- integrity — Integrity issues (hash mismatch, missing manifest entry).

## Security / Supply chain
- security — Vulnerabilities or hardening.
- signing — Signing, provenance, attestation.

## Automation / CI
- ci — Workflow, matrix, checks changes.
- generation — Policy generation / scripts.

<!-- Deprecation lifecycle labels removed while project is pre-release. Add them later if a deprecation policy is activated. -->
## Documentation-specific
- docs/migration — MIGRATION / Upgrade Notes.
- docs/changelog — CHANGELOG updates.

## Discussion & Meta
- question — Usage questions.
- decision-needed — Requires an architectural decision.
- blocked — Blocked by an external dependency.

## Misc
- good-first-issue — Good for new contributors.
- help-wanted — Community help requested.

## Color recommendations (optional)
(Set these when creating labels in the UI)
- type/*: shades of blue (#1D76DB, #0E8A16)
- priority/*: red (#B60205), orange (#D93F0B), yellow (#FBCA04)
- risk/*: purple gradient (#A371F7, #D4C5F9)
- semver/*: major (#B60205), minor (#0E8A16), patch (#1D76DB)
- security: #E99695
<!-- Deprecation-related label colors reserved but labels are not active while project is pre-release. -->
-- drift / integrity: #5319E7 / #0052CC

## Usage Guidelines
1. Each issue should have exactly one type label (type/*).
2. Add a SemVer label only if the change will potentially be released.
3. For policies: include type/policy-* + risk/* (if applicable) + semver/* (if it affects versioning).
4. For pre-release work, avoid adding deprecation labels or migration flow. Introduce deprecation labels and migration guidance only after the first public release.
5. If CI detects drift — auto-label drift.

## Automation (ideas)
- GitHub Action: when files under `files/` change, add type/policy-update.
- Parse diff: new files -> type/policy-add.
- Enforce transitions (audit -> enforce) -> risk/high + semver/minor (or major, if breaking).

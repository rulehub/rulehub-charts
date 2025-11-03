# hack/release

Release packaging and supply-chain utilities:
- package and publish artifacts (OCI)
- optional signing, SBOM generation, vulnerability scan and attestations
- pre-pack cleanup: remove placeholder files from staged chart

Back-compat note: All original entrypoints remain at `hack/*.sh` as thin wrappers that exec these scripts.

# hack/gen

Generation scripts for curated artifacts and derived files:
- manifest, integrity, and snapshot generation
- values/policy/risk tables and plugin index
- core policy sets and deprecation stubs

Back-compat note: Top-level `hack/*.sh` entrypoints remain as thin wrappers that exec scripts here.
# hack/gen

Generation scripts for producing derived artifacts used by the chart and CI:
- manifests, integrity and snapshot hashes
- values/risk tables and policy indices
- Gatekeeper/Kyverno generated sets

Note: All original entrypoints remain at `hack/*.sh` as thin wrappers that delegate here, so CI/Makefile/docs keep working unchanged.

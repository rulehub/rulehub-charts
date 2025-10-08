# Snapshot Testing

This directory stores golden snapshot manifests for Helm template regression tests.

Workflow:
1. Generate baseline: `hack/generate-snapshots.sh values.yaml snapshots/baseline`
2. Commit the `snapshots/baseline` directory.
3. In CI / PRs run `hack/compare-snapshots.sh snapshots/baseline` to detect template changes.

Regenerating:
If a legitimate template change occurs, regenerate baseline and commit (ensure change is reviewed).

Index file `_index.txt` lists documents in deterministic order.

# Drift check vs core index.json

This chart can verify drift between local policy IDs (rulehub.id in files/*) and the core RuleHub plugin index (packages[].id) published on GitHub Pages.

## Default source

- By default, the script uses the stable, published URL:
  - https://rulehub.github.io/rulehub/plugin-index/index.json
- You can override the source with an env var or a local path.

## How to run

- Quick check (won't fail the build on drift):

```bash
make pre-commit-all
```

Notes:
- In the manual stage, `verify-drift-index` runs with `DRIFT_ALLOW=true` by default to avoid failing.
- The script auto-selects the default URL unless `INDEX_JSON` is set or a local fallback exists.

- Strict drift check (fail on drift):

```bash
DRIFT_ALLOW=false make pre-commit-all
```

- Custom source (URL or path):

```bash
INDEX_JSON=/absolute/path/to/index.json make pre-commit-all
# or
INDEX_JSON=https://rulehub.github.io/rulehub/plugin-index/index.json make pre-commit-all
```

## Freeze and removed-without-deprecation checks

To enable additional lifecycle checks that require a reference point, set REF:

```bash
REF=<tag-or-commit> make pre-commit-all
```

These checks are skipped if REF is not provided.

## Under the hood

- Entrypoint: `hack/verify-drift-index.sh`
  - Accepts file paths and http/https URLs.
  - Downloads URLs via curl to a temp file and validates JSON with `jq`.
  - Falls back to the default published URL if no input is supplied.
- Comparator: `hack/drift/compare-index.sh`
  - Compares sets of IDs, prints Added (local-only) and Missing (index-only).
  - Exits non-zero on drift unless `DRIFT_ALLOW=true`.

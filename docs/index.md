---
title: RuleHub Charts
---

# RuleHub Charts

This site hosts the RuleHub Helm chart repository and documentation for the `rulehub-policies` chart.

- Chart repo URL (for Helm): `https://rulehub.github.io/rulehub-charts`
- Index file: [index.yaml](/rulehub-charts/index.yaml)
- Source repository: [github.com/rulehub/rulehub-charts](https://github.com/rulehub/rulehub-charts)

## Quick start

Add the repository and explore charts:

```bash
helm repo add rulehub https://rulehub.github.io/rulehub-charts
helm repo update
helm search repo rulehub
```

Install the `rulehub-policies` chart (preview with dry-run first):

```bash
helm install rulehub-policies rulehub/rulehub-policies \
  --namespace rulehub-policies --create-namespace \
  --dry-run
```

See the main [README](../README.md) for full usage, values, profiles, governance, and supply-chain details. Helpful docs:

- [VALUES_TABLE.md](../VALUES_TABLE.md) — all configurable values
- [docs/reproducible-build.md](./reproducible-build.md) — determinism and integrity
- [docs/enforce-policies.md](./enforce-policies.md) — enforcement modes

## Helm repository endpoint

Helm clients fetch `index.yaml` at the root of this site. If you browse here, you’ll see this landing page; programmatic consumers should use the repository URL above.

---

If this page is visible, GitHub Pages is configured correctly. If you still see a 404 at the site root, set GitHub Pages source to "Deploy from branch" and choose either `main / (root)` or `main / /docs` in repository settings.

# Drift check against core index.json
drift-compare: ## Compare local rulehub.id annotations with core index.json (INDEX=path)
	@if [ -z "$(INDEX)" ]; then echo 'Usage: make drift-compare INDEX=../core/dist/index.json'; exit 2; fi
	bash hack/drift/compare-index.sh $(INDEX)
drift-verify: ## Verify no drift vs core index.json (auto-discovery or CORE_INDEX=/path) (fails on drift)
	bash hack/verify-drift-index.sh $(INDEX)
SHELL := /bin/bash

# Tools
CT ?= ct
HELM_DOCS ?= helm-docs
CHART_DIR := .
PRE_COMMIT_VENV ?= /tmp/.venv-precommit
PRE_COMMIT_HOME_DIR ?= /tmp/.pre-commit-cache

.PHONY: help lint docs test deps values-table pre-commit-install pre-commit-run render-verify policies-sync disable-diff id-name-align

help:
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sed -E 's/:.*?#?#/\t- /'

deps: ## Add any helm repos required (placeholder)
	@echo "(add helm repo commands here if needed)"

lint: ## Run helm and chart-testing linters
	helm lint $(CHART_DIR) || true
	$(CT) lint --config .ct.yaml || true

ct-install: ## Dry-run install with ct
	$(CT) install --config .ct.yaml --helm-extra-args "--timeout 2m" --debug || true

docs: ## Generate / refresh Helm docs
	$(HELM_DOCS)

format: ## Placeholder for formatting (yaml, etc.)
	@echo "Nothing to format explicitly (yaml.formatOnSave in VSCode)."

all: lint docs

package: ## Package the chart into a tgz (uses Chart.yaml version)
	helm package $(CHART_DIR)

package-clean: ## Package chart excluding placeholder policy YAML (removes *placeholder*.yaml)
	./hack/prepack-remove-placeholders.sh

oci-push: ## Push packaged chart (CHART_VERSION required) usage: make oci-push CHART_VERSION=0.1.0 ORG=your-org
	@if [ -z "$(CHART_VERSION)" ]; then echo 'Set CHART_VERSION'; exit 2; fi; \
	if [ -z "$(ORG)" ]; then echo 'Set ORG (GitHub org/user)'; exit 2; fi; \
	helm push rulehub-policies-$(CHART_VERSION).tgz oci://ghcr.io/$(ORG)/charts

sign-keyless: ## Keyless (OIDC) sign pushed OCI chart (COSIGN_EXPERIMENTAL=1) usage: make sign-keyless CHART_VERSION=0.1.0 ORG=your-org
	@if [ -z "$(CHART_VERSION)" ] || [ -z "$(ORG)" ]; then echo 'Set CHART_VERSION and ORG'; exit 2; fi; \
	COSIGN_EXPERIMENTAL=1 cosign sign ghcr.io/$(ORG)/charts/rulehub-policies:$(CHART_VERSION)

verify-signature: ## Verify signature of OCI chart
	@if [ -z "$(CHART_VERSION)" ] || [ -z "$(ORG)" ]; then echo 'Set CHART_VERSION and ORG'; exit 2; fi; \
	COSIGN_EXPERIMENTAL=1 cosign verify ghcr.io/$(ORG)/charts/rulehub-policies:$(CHART_VERSION) >/dev/null && echo 'Signature OK'

attest-sbom: ## Generate SBOM (syft) and attach as Cosign attestation
	@if [ -z "$(CHART_VERSION)" ] || [ -z "$(ORG)" ]; then echo 'Set CHART_VERSION and ORG'; exit 2; fi; \
	syft oci:ghcr.io/$(ORG)/charts/rulehub-policies:$(CHART_VERSION) -o spdx-json=sbom.spdx.json; \
	cosign attest --predicate sbom.spdx.json --type spdx ghcr.io/$(ORG)/charts/rulehub-policies:$(CHART_VERSION)

supply-chain-pipeline: ## Run end-to-end supply chain pipeline (set ORG, CHART_VERSION) (package->push->sign->sbom->scan->attest)
	@if [ -z "$(CHART_VERSION)" ] || [ -z "$(ORG)" ]; then echo 'Set CHART_VERSION and ORG'; exit 2; fi; \
	bash hack/pipeline-supply-chain.sh --org $(ORG) --version $(CHART_VERSION) --sign --sbom --scan --attest-sbom --attest-vuln || exit $$?

vulns-verify: ## Vulnerability gate: fail if CRITICAL vulns found (ORG, CHART_VERSION) (args: SEVERITY=CRITICAL ALLOW=0)
	@if [ -z "$(CHART_VERSION)" ] || [ -z "$(ORG)" ]; then echo 'Set CHART_VERSION and ORG'; exit 2; fi; \
	bash hack/verify-vulns.sh --org $(ORG) --version $(CHART_VERSION) --severity $(if [ -n "$(SEVERITY)" ]; then echo $(SEVERITY); else echo CRITICAL; fi) --allow $(if [ -n "$(ALLOW)" ]; then echo $(ALLOW); else echo 0; fi)

provenance: ## Generate SLSA provenance (CHART_VERSION required) -> slsa-provenance.json
	@if [ -z "$(CHART_VERSION)" ]; then echo 'Set CHART_VERSION'; exit 2; fi; \
	bash hack/generate-provenance.sh --version $(CHART_VERSION) --package --out slsa-provenance.json

values-table: ## Regenerate VALUES_TABLE.md from values.yaml
	./hack/gen-values-table.sh

policy-table: ## Generate policy status table (policy key | framework | enforce? | description)
	./hack/gen-policy-table.sh

render-verify: ## Verify rendered manifests have no disallowed patterns
	./hack/verify-render.sh .

policies-sync: ## Verify policy keys in values.yaml match files/ (gatekeeper & kyverno)
	./hack/verify-policies-sync.sh

id-name-align: ## Verify rulehub.id dotted form matches metadata.name kebab variants
	./hack/verify-id-name-alignment.sh

id-annotations: ## Verify every policy YAML has rulehub.id annotation
	./hack/verify-id-annotation.sh

enforce-rationale: ## Verify enforced Kyverno policies have rationale comments in values.yaml
	./hack/verify-enforce-rationale.sh

integrity-verify: ## Verify policy YAML integrity against manifest.json
	./hack/verify-integrity.sh

manifest: ## Generate manifest.json (inventory + hashes) and aggregate integrity hash
	bash hack/generate-manifest.sh --strict
	# Optional schema verification (non-fatal if schema tool missing)
	@if command -v jq >/dev/null 2>&1; then bash hack/verify-manifest-schema.sh || true; fi

manifest-verify: ## Validate manifest.json against schema and semantics
	./hack/verify-manifest-schema.sh || true

manifest-diff: ## Compare two manifest.json files (OLD=prev/manifest.json NEW=manifest.json) (Added/Removed/Modified)
	@if [ -z "$(OLD)" ]; then echo 'Usage: make manifest-diff OLD=path/to/old/manifest.json [NEW=manifest.json]'; exit 2; fi; \
	NEW_MANIFEST=$(if [ -n "$(NEW)" ]; then echo "$(NEW)"; else echo "manifest.json"; fi); \
	bash hack/compare-manifest.sh --old "$(OLD)" --new "$$NEW_MANIFEST"

aggregate-integrity: ## Compute aggregate integrity sha256 across all policy YAML files
	bash hack/aggregate-integrity.sh

labels-verify: ## Verify every rendered resource has chart/version label
	./hack/verify-chart-version-label.sh

generate-policies: ## Generate (or partially regenerate) policy YAMLs from core sources (env: CORE_METADATA_DIR, CORE_TEMPLATES_DIR, optional: PARTIAL=id1,id2 MANIFEST=1 DEBUG=1)
	@if [ -z "$(CORE_METADATA_DIR)" ] || [ -z "$(CORE_TEMPLATES_DIR)" ]; then \
		echo 'Usage: make generate-policies CORE_METADATA_DIR=../core/metadata CORE_TEMPLATES_DIR=../core/templates/kyverno [PARTIAL=id1,id2] [MANIFEST=1] [DEBUG=1]'; exit 2; \
	fi; \
	CORE_METADATA_DIR=$(CORE_METADATA_DIR) \
	CORE_TEMPLATES_DIR=$(CORE_TEMPLATES_DIR) \
	./hack/generate-policies.sh $(if $(PARTIAL),--partial $(PARTIAL),) $(if $(MANIFEST),--manifest,) $(if $(DEBUG),--debug,)

verify-labels: ## Alias for labels-verify (backward compatibility with docs)
	$(MAKE) labels-verify

schema-compare: ## Compare values.yaml against values.schema.json (structure & presence)
	./hack/compare-values-schema.sh

schema-coverage: ## Estimate coverage percentage of values.yaml keys present in values.schema.json
	bash hack/schema-coverage.sh

disable-diff: ## Generate unified diff to disable listed policies (usage: make disable-diff KEYS="k1 k2")
	@if [[ -z "$(KEYS)" ]]; then echo "Specify KEYS=\"policy1 policy2\"" >&2; exit 1; fi; \
	./hack/generate-disable-diff.sh $(KEYS)

semver-suggest: ## Suggest next SemVer: make semver-suggest FILE=changes.txt or STRING="Added: ..."
	@if [[ -n "$(FILE)" ]]; then \
	  ./hack/suggest-semver-bump.sh --file "$(FILE)"; \
	elif [[ -n "$(STRING)" ]]; then \
	  ./hack/suggest-semver-bump.sh --string "$(STRING)"; \
	else \
	  echo "Provide FILE= or STRING= input" >&2; exit 1; \
	fi

semver-analyze: ## Analyze manifests diff for SemVer suggestion (OLD=prev/manifest.json NEW=manifest.json)
	@if [[ -z "$(OLD)" ]] || [[ -z "$(NEW)" ]]; then echo 'Usage: make semver-analyze OLD=prev/manifest.json NEW=manifest.json'; exit 2; fi; \
	./hack/semver-analyze.sh --old-manifest $(OLD) --new-manifest $(NEW)

changelog-generate: ## Generate / prepend CHANGELOG.md (VERSION=X.Y.Z OLD=prev/manifest.json NEW=manifest.json)
	@if [[ -z "$(VERSION)" ]] || [[ -z "$(OLD)" ]] || [[ -z "$(NEW)" ]]; then echo 'Usage: make changelog-generate VERSION=X.Y.Z OLD=prev/manifest.json NEW=manifest.json'; exit 2; fi; \
	./hack/generate-changelog.sh --version $(VERSION) --old-manifest $(OLD) --new-manifest $(NEW)

pseudo-diff: ## Render current chart and previous release (PREV=chart-0.1.0.tgz) and show normalized diff
	@if [[ -z "$(PREV)" ]]; then echo 'Usage: make pseudo-diff PREV=path/to/old.tgz [VALUES=values.yaml]'; exit 2; fi; \
	VALUES_FILE=${VALUES:-values.yaml}; \
	bash hack/pseudo-diff-template.sh --prev "$(PREV)" --values "$${VALUES_FILE}" || exit $$?

pre-commit-install: ## Install git pre-commit hooks if pre-commit is available
	@if command -v pre-commit >/dev/null 2>&1; then \
	  pre-commit install; \
	  echo "pre-commit hooks installed"; \
	else \
	  echo "pre-commit not found (install via 'pipx install pre-commit')"; \
	fi

pre-commit-run: ## Run pre-commit hooks in isolated venv (no repo pollution)
	@bash -c '\
	  set -euo pipefail; \
	  python3 -m venv $(PRE_COMMIT_VENV); \
	  source $(PRE_COMMIT_VENV)/bin/activate; \
	  python -m pip install --upgrade pip >/dev/null; \
	  python -m pip install "pre-commit>=3.6,<4" >/dev/null; \
	  PRE_COMMIT_HOME=$(PRE_COMMIT_HOME_DIR) pre-commit run --all-files \
	'

pre-commit-all: ## Run pre-commit default + manual hooks (full verification bundle)
	@set -euo pipefail; \
	python3 -m venv $(PRE_COMMIT_VENV); \
	source $(PRE_COMMIT_VENV)/bin/activate; \
	python -m pip install --upgrade pip >/dev/null; \
	python -m pip install "pre-commit>=3.6,<4" >/dev/null; \
	PRE_COMMIT_HOME=$(PRE_COMMIT_HOME_DIR) pre-commit run --all-files; \
	SKIP_MANUAL=""; \
	if [ -z "$${REF:-}" ]; then SKIP_MANUAL="$$SKIP_MANUAL,freeze-verify,removed-without-deprecation-verify"; fi; \
	SKIP_MANUAL=$${SKIP_MANUAL#,}; \
	if [ -n "$$SKIP_MANUAL" ]; then \
	  echo "[pre-commit-all] Skipping manual hooks: $$SKIP_MANUAL (set REF and/or INDEX_JSON to enable)"; \
	fi; \
	SKIP=$$SKIP_MANUAL DRIFT_ALLOW=$${DRIFT_ALLOW:-true} PRE_COMMIT_HOME=$(PRE_COMMIT_HOME_DIR) pre-commit run --all-files --hook-stage manual

snapshots-generate: ## Generate current snapshot documents (golden) into snapshots/current
	./hack/generate-snapshots.sh values.yaml snapshots/current

snapshot-hashes: ## Generate per-file sha256 hashes for snapshot directory (SNAP_DIR=snapshots/current)
	./hack/generate-snapshot-hashes.sh $(if [ -n "$(SNAP_DIR)" ]; then echo $(SNAP_DIR); else echo snapshots/current; fi)

snapshots-compare: ## Compare baseline vs current generated snapshots (fail on diff)
	./hack/compare-snapshots.sh snapshots/baseline values.yaml

template-diff: ## Diff current helm template vs git ref (REF=git-ref) (VALUES=values.yaml Y=1 CTX=5 NO_COLOR=1)
	@if [[ -z "$(REF)" ]]; then echo 'Usage: make template-diff REF=<git-ref> [VALUES=values.yaml] [Y=1] [CTX=5]'; exit 2; fi; \
	VALUES_FILE=${VALUES:-values.yaml}; \
	bash hack/template-diff.sh --ref "$(REF)" --values "$$VALUES_FILE" $(if $(Y),--y,) $(if $(NO_COLOR),--no-color,) $(if $(CTX),--context $(CTX),)

verify-deterministic: ## Ensure two successive helm template runs are identical
	./hack/verify-deterministic.sh

verify: ## Run key verification suite (labels, integrity, deterministic)
	$(MAKE) labels-verify
	$(MAKE) integrity-verify || true
	$(MAKE) verify-deterministic

underscore-gate: ## Verify no new underscore policy key added without dash variant (BASE=HEAD~)
	./hack/verify-underscore-gate.sh $(if $(BASE),--base $(BASE),)

helm-unit: ## Run helm-unittest test suite (requires helm unittest plugin)
	@if ! helm plugin list | grep -q unittest; then echo 'helm unittest plugin not installed (helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.1)'; exit 2; fi
	helm unittest -f "tests/*.yaml" ./

orphan-policies: ## Detect orphan policy files (no key) and dangling keys (no file)
	./hack/detect-orphan-policies.sh

deprecated-stubs-generate: ## Generate deprecated stub YAMLs for keys with deprecated_since (usage: make deprecated-stubs-generate [VALUES=values.yaml])
	./hack/generate-deprecated-stubs.sh $(if $(VALUES),--values $(VALUES),)

schema-version-verify: ## Verify values.yaml schemaVersion matches values.schema.json const
	./hack/verify-schema-version.sh

profile-matrix: ## Render matrix scenarios (minimal/full/gatekeeper-only/kyverno-only) and report resource counts
	./hack/test-profile-matrix.sh

profiles-verify: ## Verify profiles (activeProfiles) render declared policies (options: FORCE=1 QUIET=1)
	./hack/verify-profiles.sh $(if $(VALUES),--values $(VALUES),) $(if $(FORCE),--force-matrix,) $(if $(QUIET),--quiet,)

profile-consistency: ## Verify internal consistency of profiles bundles (subset, duplicates, unknown keys)
	./hack/verify-profile-consistency.sh $(if $(VALUES),--values $(VALUES),)

performance-verify: ## Verify helm template performance regression within threshold (PERF_THRESHOLD=0.20 RUNS=3) (update baseline: make performance-verify UPDATE=1)
	./hack/verify-performance.sh $(if $(UPDATE),--update,) $(if $(PERF_THRESHOLD),--threshold $(PERF_THRESHOLD),) $(if $(RUNS),--runs $(RUNS),)

fuzz-policies: ## Fuzz random enable/disable of policies to detect template crashes (RUNS=20)
	./hack/fuzz-policies.sh $(if $(RUNS),--runs $(RUNS),)

k8s-versions-section: ## Regenerate Supported Kubernetes Versions section in README.md
	bash hack/gen-supported-k8s-versions.sh

deprecation-verify: ## Verify deprecation window (OLD_VALUES=prev/values.yaml WINDOW=2)
	bash hack/verify-deprecation-window.sh $(if $(OLD_VALUES),--old-values $(OLD_VALUES),) $(if $(WINDOW),--window $(WINDOW),)

soft-deletion-verify: ## Verify deprecated stub files are removed after soft deletion window (WINDOW=2)
	bash hack/verify-soft-deletion.sh $(if $(WINDOW),--window $(WINDOW),)

stub-not-enforce-verify: ## Verify deprecated stub policies are not enforced
	bash hack/verify-stub-not-enforce.sh $(if $(VALUES),--values $(VALUES),)

freeze-verify: ## Verify release freeze (REF=git-ref WINDOW of allowed changes) usage: make freeze-verify REF=v0.1.0 [ALLOW_CRITICAL=1 ALLOW_HACK=1]
	@if [[ -z "$(REF)" ]]; then echo 'Usage: make freeze-verify REF=<git-ref> [ALLOW_CRITICAL=1] [ALLOW_HACK=1]'; exit 2; fi; \
	 bash hack/verify-freeze.sh --ref $(REF) $(if $(ALLOW_CRITICAL),--allow-critical,) $(if $(ALLOW_HACK),--allow-hack,)

removed-without-deprecation-verify: ## Verify removed policy files were previously deprecated (REF=previous-tag)
	@if [[ -z "$(REF)" ]]; then echo 'Usage: make removed-without-deprecation-verify REF=<prev-tag>'; exit 2; fi; \
	 bash hack/verify-removed-without-deprecation.sh --ref $(REF)

release-publish: ## Package, tag (signed), push, sign, sbom, scan, provenance, attest (CHART_VERSION= X.Y.Z ORG=org) usage: make release-publish CHART_VERSION=0.1.0 ORG=myorg SIGN=1 SBOM=1 SCAN=1 PROVENANCE=1 ATTEST=1 PUSH_TAG=1
	@if [[ -z "$(CHART_VERSION)" ]] || [[ -z "$(ORG)" ]]; then echo 'Usage: make release-publish CHART_VERSION=X.Y.Z ORG=org [SIGN=1] [SBOM=1] [SCAN=1] [ATTEST=1] [PUSH_TAG=1]'; exit 2; fi; \
	 bash hack/publish-release-artifacts.sh --version $(CHART_VERSION) --org $(ORG) $(if $(SIGN),--sign,) $(if $(SBOM),--sbom,) $(if $(SCAN),--scan,) $(if $(PROVENANCE),--provenance,) $(if $(ATTEST),--attest,) $(if $(PUSH_TAG),--push-tag,)

build-annotations-verify: ## Verify build annotations present when configured (VALUES=values.yaml)
	./hack/verify-build-annotations.sh $(if $(VALUES),$(VALUES),)

size-verify: ## Verify total rendered manifest size within threshold (THRESHOLD=256000, VALUES=values.yaml)
	./hack/verify-size.sh $(if $(THRESHOLD),--threshold $(THRESHOLD),) $(if $(VALUES),--values $(VALUES),)

integrity-configmap-verify: ## Verify integrity ConfigMap exported when enabled (VALUES=values.yaml)
	./hack/verify-integrity-configmap.sh $(if $(VALUES),--values $(VALUES),)

integrity-all: ## Generate manifest + aggregate hash, verify integrity & README badge
	$(MAKE) manifest
	$(MAKE) aggregate-integrity
	$(MAKE) integrity-verify || true
	bash hack/verify-integrity-badge.sh

dev-validate: ## Fast validate only changed YAML policy files (args: BASE=ref STAGED=1 ALL=1)
	./hack/dev-validate-changed.sh $(if $(BASE),--base $(BASE),) $(if $(STAGED),--staged,) $(if $(ALL),--all,)

risk-test-plan: ## Generate prioritized policy test plan (FORMAT=markdown|text|json LIMIT_LOW=10)
	bash hack/prioritize-risk-tests.sh $(if $(FORMAT),--format $(FORMAT),) $(if $(LIMIT_LOW),--limit-low $(LIMIT_LOW),)

kubeconform-verify: ## Verify kubeconform artifact checksum (OS=linux ARCH=amd64 VERSION=v0.7.0 INSTALL=1 to install)
	bash hack/verify-kubeconform-checksum.sh $(if $(VERSION),--version $(VERSION),) $(if $(OS),--os $(OS),) $(if $(ARCH),--arch $(ARCH),) $(if $(INSTALL),--install,)

kind-smoke: ## Ephemeral kind install/uninstall smoke test (env: CLUSTER_NAME=rulehub-charts-smoke NAMESPACE=policies RELEASE=rulehub-policies VALUES_FILE=values.yaml)
	bash hack/kind-smoke.sh

# Backstage plugin index helpers
.PHONY: generate-plugin-index verify-plugin-index

generate-plugin-index: ## Generate dist/index.json for the Backstage plugin
	@bash hack/generate-plugin-index.sh

verify-plugin-index: ## Verify dist/index.json is current and valid
	@bash hack/verify-plugin-index.sh

.PHONY: plugin-index-sync
plugin-index-sync: ## Export metadata from core and generate/verify charts plugin index (CORE_DIR=../rulehub)
	@set -euo pipefail; \
	CORE_DIR=$${CORE_DIR:-../rulehub}; \
	if [ ! -d "$$CORE_DIR" ]; then echo "CORE_DIR not found: $$CORE_DIR" >&2; exit 2; fi; \
	make -C "$$CORE_DIR" export-plugin-metadata; \
	RULEHUB_PLUGIN_METADATA_JSON="$$CORE_DIR/dist/plugin-index-metadata.json" bash hack/generate-plugin-index.sh; \
	bash hack/verify-plugin-index.sh

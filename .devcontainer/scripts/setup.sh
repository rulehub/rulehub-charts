#!/usr/bin/env bash
set -euo pipefail

# Fail fast if we don't have write access to system dirs required later (common cause of curl error 23)
for d in /usr/local/bin /etc /var; do
  if [ ! -w "$d" ]; then
    echo "[devcontainer][warn] Current user $(id -u):$(id -g) lacks write permission to $d. Attempting to use sudo where necessary." >&2
    HAVE_SUDO=1
  fi
done

run_cmd() {
  # Wrapper to transparently use sudo when needed
  if [ -n "${HAVE_SUDO:-}" ]; then
    sudo bash -c "$*"
  else
    bash -c "$*"
  fi
}

if [ -f /tmp/.devcontainer_setup_done ]; then
  echo "Setup already completed. Skipping."
  exit 0
fi

# Version pins (adjust as needed)
YQ_VERSION=v4.44.1
HELM_DOCS_VERSION=v1.14.2
CT_VERSION=v3.11.0
PRE_COMMIT_VERSION=3.7.1
SYFT_VERSION=v1.18.0
COSIGN_VERSION=v2.2.4

echo "[devcontainer] Installing base packages..."
run_cmd "apt-get update -y >/dev/null 2>&1" || { echo "[devcontainer][error] apt-get update failed" >&2; exit 1; }
run_cmd "apt-get install -y --no-install-recommends jq curl unzip ca-certificates bash-completion git gnupg python3 python3-pip pipx >/dev/null 2>&1" || { echo "[devcontainer][error] apt-get install failed" >&2; exit 1; }
run_cmd "rm -rf /var/lib/apt/lists/*" || true

echo "[devcontainer] Installing yq ${YQ_VERSION}..."
if ! command -v yq >/dev/null; then
  YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
  TMP_YQ="$(mktemp)" || { echo "[devcontainer][error] mktemp failed" >&2; exit 1; }
  if ! curl -fSL "$YQ_URL" -o "$TMP_YQ"; then
    echo "[devcontainer][error] Failed downloading yq from $YQ_URL" >&2
    rm -f "$TMP_YQ" || true
    exit 1
  fi
  # Basic size sanity check (> 1MB)
  if [ "$(stat -c%s "$TMP_YQ")" -lt 1000000 ]; then
    echo "[devcontainer][error] Downloaded yq binary seems too small; aborting." >&2
    ls -l "$TMP_YQ" >&2 || true
    rm -f "$TMP_YQ" || true
    exit 1
  fi
  run_cmd "install -m 0755 $TMP_YQ /usr/local/bin/yq" || { echo "[devcontainer][error] Failed to install yq" >&2; exit 1; }
  rm -f "$TMP_YQ" || true
fi

echo "[devcontainer] Installing Helm (if missing)..."
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
fi

echo "[devcontainer] Installing helm-docs ${HELM_DOCS_VERSION}..."
if ! command -v helm-docs >/dev/null; then
  HD_URL="https://github.com/norwoodj/helm-docs/releases/download/${HELM_DOCS_VERSION}/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz"
  if ! curl -fSL "$HD_URL" | run_cmd "tar -xz -C /usr/local/bin helm-docs"; then
    echo "[devcontainer][error] Failed installing helm-docs from $HD_URL" >&2
    exit 1
  fi
fi

echo "[devcontainer] Installing chart-testing ct ${CT_VERSION}..."
if ! command -v ct >/dev/null; then
  CT_URL="https://github.com/helm/chart-testing/releases/download/${CT_VERSION}/chart-testing_${CT_VERSION#v}_linux_amd64.tar.gz"
  TMP_DIR="$(mktemp -d)" || { echo "[devcontainer][error] mktemp failed" >&2; exit 1; }
  if curl -fSL "$CT_URL" -o "$TMP_DIR/ct.tgz"; then
    if tar -tzf "$TMP_DIR/ct.tgz" >/dev/null 2>&1; then
      tar -xzf "$TMP_DIR/ct.tgz" -C "$TMP_DIR" || { echo "[devcontainer][error] Extract ct archive failed" >&2; exit 1; }
      # Find ct binary inside extracted structure
      CT_BIN="$(find "$TMP_DIR" -maxdepth 3 -type f -name ct -perm -111 | head -n1)"
      if [ -n "$CT_BIN" ]; then
        run_cmd "install -m 0755 $CT_BIN /usr/local/bin/ct" || { echo "[devcontainer][error] Failed to install ct" >&2; exit 1; }
      else
        echo "[devcontainer][error] ct binary not found in archive" >&2
        exit 1
      fi
    else
      echo "[devcontainer][error] Invalid ct archive downloaded" >&2
      exit 1
    fi
  else
    echo "[devcontainer][error] Download ct failed from $CT_URL" >&2
    exit 1
  fi
fi
echo "[devcontainer] Installing syft ${SYFT_VERSION}..."
if ! command -v syft >/dev/null; then
  SYFT_URL="https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/syft_${SYFT_VERSION#v}_$(uname -s)_$(uname -m).tar.gz"
  TMP_DIR="$(mktemp -d)" || { echo "[devcontainer][error] mktemp failed" >&2; exit 1; }
  if curl -fSL "$SYFT_URL" -o "$TMP_DIR/syft.tgz"; then
    tar -xzf "$TMP_DIR/syft.tgz" -C "$TMP_DIR" || { echo "[devcontainer][error] Extract syft archive failed" >&2; exit 1; }
    SYFT_BIN="$(find "$TMP_DIR" -name syft -type f -perm -111 | head -n1)"
    if [ -n "$SYFT_BIN" ]; then
      run_cmd "install -m 0755 $SYFT_BIN /usr/local/bin/syft" || { echo "[devcontainer][error] Failed to install syft" >&2; exit 1; }
    else
      echo "[devcontainer][error] syft binary not found in archive" >&2
      exit 1
    fi
  else
    echo "[devcontainer][error] Download syft failed from $SYFT_URL" >&2
    exit 1
  fi
  rm -rf "$TMP_DIR" || true
fi

echo "[devcontainer] Installing cosign ${COSIGN_VERSION}..."
if ! command -v cosign >/dev/null; then
  COSIGN_URL="https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
  if ! curl -fSL "$COSIGN_URL" -o /usr/local/bin/cosign; then
    echo "[devcontainer][error] Failed downloading cosign from $COSIGN_URL" >&2
    exit 1
  fi
  run_cmd "chmod +x /usr/local/bin/cosign" || { echo "[devcontainer][error] Failed to make cosign executable" >&2; exit 1; }
fi
  echo "[devcontainer] Installing pre-commit ${PRE_COMMIT_VERSION} via pipx..."
  run_cmd "pipx install pre-commit==${PRE_COMMIT_VERSION}" || echo "[devcontainer][warn] pipx pre-commit install failed (non-fatal)" >&2
  if ! command -v pre-commit >/dev/null && [ -x /root/.local/bin/pre-commit ]; then
    echo "[devcontainer] Exposing pre-commit via /usr/local/bin symlink..."
    run_cmd "ln -sf /root/.local/bin/pre-commit /usr/local/bin/pre-commit" || echo "[devcontainer][warn] Failed to create pre-commit symlink (non-fatal)" >&2
  fi
  # Ensure pipx bin dir on PATH for future shells
  if ! grep -q 'pipx/bin' /etc/profile 2>/dev/null; then
    run_cmd "bash -c 'echo export PATH=\"\$PATH:\$HOME/.local/bin\" >> /etc/profile'" || true
  fi
  if command -v pre-commit >/dev/null && [ -f /workspaces/rulehub-charts/.pre-commit-config.yaml ]; then
    echo "[devcontainer] Initializing pre-commit hooks..."
    (cd /workspaces/rulehub-charts && pre-commit install || echo "[devcontainer][warn] pre-commit install step failed (non-fatal)" >&2)
  fi
fi

echo "[devcontainer] Enabling bash completions..."
run_cmd "mkdir -p /etc/bash_completion.d"
if command -v helm >/dev/null; then helm completion bash | run_cmd "tee /etc/bash_completion.d/helm >/dev/null"; fi
if command -v kubectl >/dev/null; then kubectl completion bash | run_cmd "tee /etc/bash_completion.d/kubectl >/dev/null"; fi

touch /tmp/.devcontainer_setup_done
echo "Dev container setup complete"

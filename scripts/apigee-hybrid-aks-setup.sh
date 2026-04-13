#!/usr/bin/env bash
# Interactive walkthrough for Apigee Hybrid v1.16 on Azure AKS (official steps 3–11).
# Docs: https://cloud.google.com/apigee/docs/hybrid/v1.16/
#
# Step 2 (download Helm charts) is pre-done in the container image; optional re-pull available.

set -euo pipefail

# Resolve real script directory (follows symlinks, e.g. /usr/bin/apigee-hybrid-aks-setup → …/scripts)
_script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    local target
    target="$(readlink "$src")"
    [[ "$target" == /* ]] || target="${dir}/${target}"
    src="$target"
  done
  cd -P "$(dirname "$src")" && pwd
}
_SCRIPT_DIR="$(_script_dir)"
unset -f _script_dir 2>/dev/null || true
# shellcheck source=scripts/misc-cli-utils.sh
source "${_SCRIPT_DIR}/misc-cli-utils.sh"

SCRIPT_VERSION="1.0.0"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.2}"
CERT_MANAGER_URL="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

# Defaults (override via environment or optional env file)
APIGEE_HELM_CHARTS_HOME="${APIGEE_HELM_CHARTS_HOME:-/workspace/apigee-hybrid/helm-charts}"
CHART_REPO="${CHART_REPO:-oci://us-docker.pkg.dev/apigee-release/apigee-hybrid-helm-charts}"
CHART_VERSION="${CHART_VERSION:-}"

# Collected during run
APIGEE_NAMESPACE="${APIGEE_NAMESPACE:-apigee}"
PROJECT_ID="${PROJECT_ID:-}"
ORG_NAME="${ORG_NAME:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
INSTALL_PROFILE="${INSTALL_PROFILE:-}" # non-prod | prod
AUTH_MODE="${AUTH_MODE:-}"             # secrets | json | vault | wif_gke | wif_other
DATA_RESIDENCY="${DATA_RESIDENCY:-n}"
CONTROL_PLANE_LOCATION="${CONTROL_PLANE_LOCATION:-}"
MONETIZATION="${MONETIZATION:-n}"
DRY_RUN_HELM="${DRY_RUN_HELM:-n}"

# Optional: docker run -e / --env-file (see --help). With APIGEE_SETUP_NONINTERACTIVE=1, prompts are skipped;
# every required value must be set in the environment (or prompt defaults apply where defined).
AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:-}"
TLS_DOMAIN="${TLS_DOMAIN:-}"
TLS_ENV_GROUP="${TLS_ENV_GROUP:-}"
INSTANCE_ID="${INSTANCE_ID:-}"
ANALYTICS_REGION="${ANALYTICS_REGION:-}"
INGRESS_GATEWAY_NAME="${INGRESS_GATEWAY_NAME:-}"
VIRTUALHOST_NAME="${VIRTUALHOST_NAME:-}"
APIGEE_ENVIRONMENT_NAME="${APIGEE_ENVIRONMENT_NAME:-}"
SSL_CERT_PATH="${SSL_CERT_PATH:-}"
SSL_KEY_PATH="${SSL_KEY_PATH:-}"
CASSANDRA_HOST_NETWORK="${CASSANDRA_HOST_NETWORK:-}"
GSA_EMAIL="${GSA_EMAIL:-}"
AUTH_MODE_CHOICE="${AUTH_MODE_CHOICE:-}"
OVERRIDES_YAML_PATH="${OVERRIDES_YAML_PATH:-}"
OVERRIDES_WIZARD_MODE="${OVERRIDES_WIZARD_MODE:-}"
HELM_ENV_RELEASE="${HELM_ENV_RELEASE:-}"

load_optional_env() {
  local f
  for f in /workspace/.env ./apigee-hybrid.env "${HOME}/.apigee-hybrid.env"; do
    if [[ -f "$f" ]]; then
      # shellcheck source=/dev/null
      set -a
      source "$f"
      set +a
      info "Loaded environment from: $f"
      return 0
    fi
  done
  return 0
}

require_tools() {
  require_cmds kubectl helm gcloud curl az jq http
}

step_prerequisites() {
  section "Step 0 — Prerequisites (AKS + Google Cloud)" "Google Cloud + Azure CLI auth and kubeconfig" cyan
  info "Official reference: install-before-begin, provisioning, and AKS cluster access."
  info "Helm charts (Step 2) are already present under APIGEE_HELM_CHARTS_HOME unless you re-pull."

  if confirm "Run 'gcloud config set project' after PROJECT_ID is known?" "n"; then
    prompt PROJECT_ID ""
    run_cmd gcloud config set project "$PROJECT_ID"
  fi

  if confirm "Run interactive 'gcloud auth login' now?" "n"; then
    run_cmd gcloud auth login
  fi

  if confirm "Run interactive 'az login' now?" "n"; then
    run_cmd az login
  fi

  if confirm "Set Azure subscription (az account set --subscription)?" "n"; then
    prompt AZURE_SUBSCRIPTION "" "Azure subscription ID or name"
    [[ -n "${AZURE_SUBSCRIPTION:-}" ]] && run_cmd az account set --subscription "$AZURE_SUBSCRIPTION"
  fi

  prompt AZURE_RESOURCE_GROUP "my-aks-rg" "Azure resource group of the AKS cluster"
  prompt CLUSTER_NAME "my-aks" "AKS cluster name"
  prompt CLUSTER_LOCATION "westeurope" "Azure region of the cluster (for k8sCluster.region)"

  if confirm "Fetch AKS credentials (az aks get-credentials)?" "y"; then
    run_cmd az aks get-credentials --resource-group "$AZURE_RESOURCE_GROUP" --name "$CLUSTER_NAME"
  fi

  if confirm "Verify cluster connectivity?" "y"; then
    run_cmd kubectl cluster-info
    run_cmd kubectl get nodes
  fi

  prompt PROJECT_ID "" "Google Cloud project ID (Apigee / GCP)"
  prompt ORG_NAME "${PROJECT_ID}" "Apigee organization name (API resource name, used in URLs)"
}

step_optional_chart_pull() {
  section "Step 2 (optional) — Re-download Helm charts (OCI)" "" cyan
  info "Image build already pulled charts into: $APIGEE_HELM_CHARTS_HOME"
  if [[ -z "$CHART_VERSION" ]]; then
    if [[ "${APIGEE_SETUP_NONINTERACTIVE:-0}" == "1" ]]; then
      info "CHART_VERSION unset — skipping optional chart re-pull."
    else
      read -r -p "CHART_VERSION to pull (empty = skip re-pull): " CHART_VERSION || true
    fi
  fi
  if [[ -z "${CHART_VERSION:-}" ]]; then
    warn "Skipping chart pull."
    return 0
  fi
  if ! confirm "Pull charts at version $CHART_VERSION into $APIGEE_HELM_CHARTS_HOME?" "n"; then
    return 0
  fi
  (
    cd "$APIGEE_HELM_CHARTS_HOME"
    local charts=(
      apigee-operator apigee-datastore apigee-env apigee-ingress-manager
      apigee-org apigee-redis apigee-telemetry apigee-virtualhost
    )
    local c
    for c in "${charts[@]}"; do
      run_cmd helm pull "${CHART_REPO}/${c}" --version "$CHART_VERSION" --untar
    done
  )
}

step_create_namespace() {
  section "Step 3 — Create the Apigee namespace" "" cyan
  prompt APIGEE_NAMESPACE "apigee" "Kubernetes namespace for hybrid runtime"
  if kubectl get namespace "$APIGEE_NAMESPACE" >/dev/null 2>&1; then
    info "Namespace '$APIGEE_NAMESPACE' already exists."
  else
    if confirm "Create namespace '$APIGEE_NAMESPACE'?" "y"; then
      run_cmd kubectl create namespace "$APIGEE_NAMESPACE"
    fi
  fi
}

ensure_create_sa_tool() {
  local tool="$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account"
  if [[ ! -f "$tool" ]]; then
    die "create-service-account not found at: $tool"
  fi
  if [[ ! -x "$tool" ]]; then
    run_cmd chmod +x "$tool"
  fi
}

step_create_service_accounts() {
  section "Step 4 — Create Google service accounts (create-service-account)" "" cyan
  ensure_create_sa_tool
  info "Choose installation profile (see Apigee docs: production vs non-production)."
  prompt INSTALL_PROFILE "non-prod" "non-prod or prod"
  INSTALL_PROFILE="${INSTALL_PROFILE:-non-prod}"
  if [[ "$INSTALL_PROFILE" != "prod" && "$INSTALL_PROFILE" != "non-prod" ]]; then
    warn "Invalid profile; defaulting to non-prod."
    INSTALL_PROFILE="non-prod"
  fi

  prompt PROJECT_ID "$PROJECT_ID" "GCP project ID"

  echo ""
  if [[ -z "${AUTH_MODE:-}" ]]; then
    info "Authentication method for hybrid (Step 5 preview — choose how keys are consumed):"
    bullet_list \
      "1) Kubernetes Secrets (recommended for guided install)" \
      "2) JSON key files inside each Helm chart directory" \
      "3) Vault (manual — see official docs only)" \
      "4) Workload Identity Federation for GKE (not applicable on AKS — documentation only)" \
      "5) Workload Identity Federation on other platforms (AKS OIDC — advanced)"
    prompt AUTH_MODE_CHOICE "1" "1=secrets 2=json 3=vault 4=wif_gke 5=wif_other"
    _am="${AUTH_MODE_CHOICE:-1}"
    case "$_am" in
      1) AUTH_MODE="secrets" ;;
      2) AUTH_MODE="json" ;;
      3) AUTH_MODE="vault" ;;
      4) AUTH_MODE="wif_gke" ;;
      5) AUTH_MODE="wif_other" ;;
      *) AUTH_MODE="secrets" ;;
    esac
  else
    info "AUTH_MODE=$AUTH_MODE (from environment) — skipping menu."
  fi

  if [[ "$AUTH_MODE" == "vault" ]]; then
    warn "Vault path is not automated here. Complete Step 4–5 using:"
    echo "  https://cloud.google.com/apigee/docs/hybrid/v1.16/install-service-accounts"
    echo "  https://cloud.google.com/apigee/docs/hybrid/v1.16/install-sa-authentication"
    info "Re-run this script from a later step (e.g. $0 tls) after Vault is configured."
    return 0
  fi

  if [[ "$AUTH_MODE" == "wif_gke" ]]; then
    warn "Skipping execution: WIF for GKE is for Google Kubernetes Engine only."
    info "On AKS use option 5 (WIF other) or Kubernetes Secrets / JSON files."
    return 0
  fi

  local sa_dir=""
  if [[ "$AUTH_MODE" == "secrets" || "$AUTH_MODE" == "wif_other" ]]; then
    sa_dir="$APIGEE_HELM_CHARTS_HOME/service-accounts"
    run_cmd mkdir -p "$sa_dir"
    if [[ "$INSTALL_PROFILE" == "prod" ]]; then
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --env prod --dir "$sa_dir" --project-id "$PROJECT_ID"
    else
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --env non-prod --dir "$sa_dir" --project-id "$PROJECT_ID"
    fi
  else
    # JSON files per chart directory (non-prod / prod paths per docs)
    if [[ "$INSTALL_PROFILE" == "non-prod" ]]; then
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --env non-prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-datastore" --project-id "$PROJECT_ID"
      local f
      f=$(find "$APIGEE_HELM_CHARTS_HOME/apigee-datastore" -maxdepth 1 -name '*-apigee-non-prod.json' -print -quit)
      if [[ -z "$f" ]]; then
        die "expected *-apigee-non-prod.json under apigee-datastore"
      fi
      local base
      base=$(basename "$f")
      run_cmd cp -f "$f" "$APIGEE_HELM_CHARTS_HOME/apigee-operator/$base"
      run_cmd cp -f "$f" "$APIGEE_HELM_CHARTS_HOME/apigee-telemetry/$base"
      run_cmd cp -f "$f" "$APIGEE_HELM_CHARTS_HOME/apigee-org/$base"
      run_cmd cp -f "$f" "$APIGEE_HELM_CHARTS_HOME/apigee-env/$base"
    else
      # prod: per-chart directories (abbreviated single command sequence from docs)
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-cassandra --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-datastore" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-guardrails --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-operator" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-logger --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-telemetry" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-mart --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-org" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-metrics --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-telemetry" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-runtime --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-env" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-synchronizer --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-env" --project-id "$PROJECT_ID"
      run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
        --profile apigee-watcher --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-org" --project-id "$PROJECT_ID"
      if confirm "Create apigee-mint-task-scheduler (Monetization)?" "n"; then
        run_cmd "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account" \
          --profile apigee-mint-task-scheduler --env prod --dir "$APIGEE_HELM_CHARTS_HOME/apigee-org" --project-id "$PROJECT_ID"
        MONETIZATION="y"
      fi
    fi
  fi
}

step_k8s_secrets() {
  section "Step 5 — Kubernetes Secrets for service accounts" "" cyan
  if [[ "$AUTH_MODE" != "secrets" ]]; then
    info "AUTH_MODE=$AUTH_MODE — skipping kubectl secret creation (not using Kubernetes Secrets path)."
    if [[ "$AUTH_MODE" == "json" ]]; then
      info "JSON file auth: no extra Step 5 actions (see docs). Proceed to TLS / overrides."
    elif [[ "$AUTH_MODE" == "wif_other" ]]; then
      step_wif_other_guidance
    fi
    return 0
  fi

  prompt APIGEE_NAMESPACE "${APIGEE_NAMESPACE:-apigee}"
  prompt PROJECT_ID "$PROJECT_ID"

  if [[ "$INSTALL_PROFILE" == "prod" ]]; then
    local base="$APIGEE_HELM_CHARTS_HOME/service-accounts"
    run_cmd bash -c "kubectl create secret generic apigee-logger-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-logger.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-guardrails-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-guardrails.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-metrics-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-metrics.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-watcher-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-watcher.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-mart-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-mart.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-synchronizer-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-synchronizer.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    run_cmd bash -c "kubectl create secret generic apigee-runtime-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-runtime.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    if [[ "$MONETIZATION" == "y" ]] || confirm "Create apigee-mint-task-scheduler-svc-account secret (Monetization)?" "n"; then
      run_cmd bash -c "kubectl create secret generic apigee-mint-task-scheduler-svc-account \
        --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-mint-task-scheduler.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
    fi
  else
    local base="$APIGEE_HELM_CHARTS_HOME/service-accounts"
    run_cmd bash -c "kubectl create secret generic apigee-non-prod-svc-account \
      --from-file=client_secret.json=$base/${PROJECT_ID}-apigee-non-prod.json -n $APIGEE_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
  fi
  warn "Optional: delete JSON files on disk after secrets exist (see official security guidance)."
}

step_wif_other_guidance() {
  section "Step 5 — Workload Identity Federation on other platforms (AKS)" "" cyan
  info "Follow: https://cloud.google.com/apigee/docs/hybrid/v1.16/install-sa-authentication (WIF on other platforms)"
  info "Enable AKS OIDC issuer: https://learn.microsoft.com/azure/aks/use-oidc-issuer"
  echo ""
  if [[ -n "${AZURE_RESOURCE_GROUP:-}" && -n "${CLUSTER_NAME:-}" ]]; then
    if confirm "Print OIDC issuer URL via Azure CLI?" "y"; then
      run_cmd az aks show -n "$CLUSTER_NAME" -g "$AZURE_RESOURCE_GROUP" --query "oidcIssuerProfile.issuerUrl" -otsv
    fi
  else
    warn "Set AZURE_RESOURCE_GROUP and CLUSTER_NAME to query OIDC issuer, or run:"
    echo '  az aks show -n CLUSTER_NAME -g RESOURCE_GROUP --query "oidcIssuerProfile.issuerUrl" -otsv'
  fi
  echo ""
  info "Enable STS API if needed:"
  echo "  gcloud services enable sts.googleapis.com --project $PROJECT_ID"
  info "Then create workload identity pool/provider and IAM bindings per Google documentation."
}

step_tls_certs() {
  section "Step 6 — TLS certificates (self-signed quickstart)" "" cyan
  if ! command -v openssl >/dev/null 2>&1; then
    die "openssl not found. Install openssl in the image or on the host."
  fi
  prompt TLS_DOMAIN "" "hostname for environment group (CN=)"
  prompt TLS_ENV_GROUP "" "name used in cert filenames (keystore_…)"
  if [[ -z "$TLS_DOMAIN" || -z "$TLS_ENV_GROUP" ]]; then
    error "TLS_DOMAIN and TLS_ENV_GROUP are required."
    return 1
  fi
  local cert_dir="$APIGEE_HELM_CHARTS_HOME/apigee-virtualhost/certs"
  run_cmd mkdir -p "$cert_dir"
  run_cmd openssl req -nodes -new -x509 \
    -keyout "$cert_dir/keystore_${TLS_ENV_GROUP}.key" \
    -out "$cert_dir/keystore_${TLS_ENV_GROUP}.pem" \
    -subj "/CN=${TLS_DOMAIN}" -days 3650
  run_cmd ls -la "$cert_dir"
  info "Use these paths in overrides.yaml virtualhosts (sslCertPath / sslKeyPath)."
}

write_overrides_nonprod_secrets() {
  local out="$1"
  prompt INSTANCE_ID "" "unique per cluster (instanceID)"
  prompt ANALYTICS_REGION "" "gcp.region / Analytics region"
  prompt INGRESS_GATEWAY_NAME "ingw1" "ingressGateways[0].name (max 17 chars)"
  prompt VIRTUALHOST_NAME "" "virtualhosts[0].name (environment group)"
  prompt APIGEE_ENVIRONMENT_NAME "" "envs[0].name (Apigee environment)"
  prompt SSL_CERT_PATH "" "sslCertPath (e.g. apigee-virtualhost/certs/keystore_${VIRTUALHOST_NAME}.pem)"
  prompt SSL_KEY_PATH "" "sslKeyPath (e.g. apigee-virtualhost/certs/keystore_${VIRTUALHOST_NAME}.key)"
  prompt CASSANDRA_HOST_NETWORK "false" "cassandra.hostNetwork true or false"

  local contract_line=""
  if [[ "$DATA_RESIDENCY" == "y" ]]; then
    prompt CONTROL_PLANE_LOCATION "$CONTROL_PLANE_LOCATION" "Control plane region slug"
    contract_line="contractProvider: https://${CONTROL_PLANE_LOCATION}-apigee.googleapis.com"
  fi

  cat >"$out" <<EOF
# Generated by apigee-hybrid-aks-setup.sh — review against official docs:
# https://cloud.google.com/apigee/docs/hybrid/v1.16/install-create-overrides

instanceID: "${INSTANCE_ID}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${ANALYTICS_REGION}

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true
${contract_line}

envs:
  - name: ${APIGEE_ENVIRONMENT_NAME}
    serviceAccountSecretRefs:
      synchronizer: apigee-non-prod-svc-account
      runtime: apigee-non-prod-svc-account

cassandra:
  hostNetwork: ${CASSANDRA_HOST_NETWORK}
  replicaCount: 3
  storage:
    storageSize: 100Gi
  resources:
    requests:
      cpu: 2
      memory: 4Gi
  maxHeapSize: 2048M
  heapNewSize: 400M

ingressGateways:
  - name: ${INGRESS_GATEWAY_NAME}
    replicaCountMin: 1
    replicaCountMax: 3

virtualhosts:
  - name: ${VIRTUALHOST_NAME}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${INGRESS_GATEWAY_NAME}
    sslCertPath: ${SSL_CERT_PATH}
    sslKeyPath: ${SSL_KEY_PATH}

guardrails:
  serviceAccountRef: apigee-non-prod-svc-account
mart:
  serviceAccountRef: apigee-non-prod-svc-account
connectAgent:
  serviceAccountRef: apigee-non-prod-svc-account
logger:
  serviceAccountRef: apigee-non-prod-svc-account
metrics:
  serviceAccountRef: apigee-non-prod-svc-account
watcher:
  serviceAccountRef: apigee-non-prod-svc-account
EOF
}

write_overrides_prod_secrets() {
  local out="$1"
  prompt INSTANCE_ID "" "unique per cluster (instanceID)"
  prompt ANALYTICS_REGION "" "gcp.region / Analytics region"
  prompt INGRESS_GATEWAY_NAME "ingw1" "ingressGateways[0].name"
  prompt VIRTUALHOST_NAME "" "virtualhosts[0].name (environment group)"
  prompt APIGEE_ENVIRONMENT_NAME "" "envs[0].name (Apigee environment)"
  prompt SSL_CERT_PATH "" "sslCertPath"
  prompt SSL_KEY_PATH "" "sslKeyPath"
  prompt CASSANDRA_HOST_NETWORK "false" "cassandra.hostNetwork true or false"

  local contract_line=""
  if [[ "$DATA_RESIDENCY" == "y" ]]; then
    prompt CONTROL_PLANE_LOCATION "$CONTROL_PLANE_LOCATION" "Control plane region slug"
    contract_line="contractProvider: https://${CONTROL_PLANE_LOCATION}-apigee.googleapis.com"
  fi

  local mint_block=""
  if [[ "$MONETIZATION" == "y" ]]; then
    mint_block="mintTaskScheduler:
  serviceAccountRef: apigee-mint-task-scheduler-svc-account"
  fi

  cat >"$out" <<EOF
# Generated by apigee-hybrid-aks-setup.sh — review for production sizing and policies.

instanceID: "${INSTANCE_ID}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${ANALYTICS_REGION}

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true
${contract_line}

envs:
  - name: ${APIGEE_ENVIRONMENT_NAME}
    serviceAccountSecretRefs:
      synchronizer: apigee-synchronizer-svc-account
      runtime: apigee-runtime-svc-account

cassandra:
  hostNetwork: ${CASSANDRA_HOST_NETWORK}
  replicaCount: 3
  storage:
    storageSize: 500Gi
  resources:
    requests:
      cpu: 7
      memory: 15Gi
  maxHeapSize: 8192M
  heapNewSize: 1200M

ingressGateways:
  - name: ${INGRESS_GATEWAY_NAME}
    replicaCountMin: 2
    replicaCountMax: 10

virtualhosts:
  - name: ${VIRTUALHOST_NAME}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${INGRESS_GATEWAY_NAME}
    sslCertPath: ${SSL_CERT_PATH}
    sslKeyPath: ${SSL_KEY_PATH}

guardrails:
  serviceAccountRef: apigee-guardrails-svc-account
mart:
  serviceAccountRef: apigee-mart-svc-account
connectAgent:
  serviceAccountRef: apigee-mart-svc-account
logger:
  enabled: true
  serviceAccountRef: apigee-logger-svc-account
metrics:
  serviceAccountRef: apigee-metrics-svc-account
watcher:
  serviceAccountRef: apigee-watcher-svc-account
${mint_block}
EOF
}

write_overrides_wif_nonprod() {
  local out="$1"
  prompt GSA_EMAIL "" "gcp.workloadIdentity.gsa (e.g. apigee-non-prod@PROJECT.iam.gserviceaccount.com)"
  prompt INSTANCE_ID "" "unique per cluster (instanceID)"
  prompt ANALYTICS_REGION "" "gcp.region (Analytics)"
  prompt INGRESS_GATEWAY_NAME "ingw1" "ingressGateways[0].name"
  prompt VIRTUALHOST_NAME "" "virtualhosts[0].name"
  prompt APIGEE_ENVIRONMENT_NAME "" "envs[0].name"
  prompt SSL_CERT_PATH "" "sslCertPath"
  prompt SSL_KEY_PATH "" "sslKeyPath"
  prompt CASSANDRA_HOST_NETWORK "false" "cassandra.hostNetwork true or false"

  cat >"$out" <<EOF
# WIF on other platforms — fill workloadIdentity details per docs (pool/provider IDs, etc.)

instanceID: "${INSTANCE_ID}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${ANALYTICS_REGION}
  workloadIdentity:
    enabled: true
    gsa: "${GSA_EMAIL}"

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true

envs:
  - name: ${APIGEE_ENVIRONMENT_NAME}

cassandra:
  hostNetwork: ${CASSANDRA_HOST_NETWORK}
  replicaCount: 3
  storage:
    storageSize: 100Gi
  resources:
    requests:
      cpu: 2
      memory: 4Gi
  maxHeapSize: 2048M
  heapNewSize: 400M

ingressGateways:
  - name: ${INGRESS_GATEWAY_NAME}
    replicaCountMin: 1
    replicaCountMax: 3

virtualhosts:
  - name: ${VIRTUALHOST_NAME}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${INGRESS_GATEWAY_NAME}
    sslCertPath: ${SSL_CERT_PATH}
    sslKeyPath: ${SSL_KEY_PATH}
EOF
}

write_overrides_json_stub() {
  local out="$1"
  cat >"$out" <<EOF
# Stub for "JSON files" authentication — finish using the JSON files tab in:
# https://cloud.google.com/apigee/docs/hybrid/v1.16/install-create-overrides
#
# Non-prod: one key file per chart directory (e.g. ${PROJECT_ID}-apigee-non-prod.json under each chart).
# Prod: per-component JSON files next to each chart as created by create-service-account.

instanceID: "REPLACE_ME"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: REPLACE_ANALYTICS_REGION

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true

# Add envs, cassandra, ingressGateways, virtualhosts, and per-component service account
# file references exactly as in the official JSON files examples for your profile.
EOF
}

step_overrides() {
  section "Step 7 — overrides.yaml" "" cyan
  [[ -n "${INSTALL_PROFILE:-}" ]] || INSTALL_PROFILE="non-prod"
  [[ -n "${AUTH_MODE:-}" ]] || AUTH_MODE="secrets"
  if confirm "Set data residency / regional control plane (contractProvider)?" "n"; then
    DATA_RESIDENCY="y"
    prompt CONTROL_PLANE_LOCATION "" "e.g. europe-west1"
  else
    DATA_RESIDENCY="n"
  fi

  local _default_out="${OVERRIDES_YAML_PATH:-$APIGEE_HELM_CHARTS_HOME/overrides.yaml}"
  info "Default output path: $_default_out"
  prompt OVERRIDES_YAML_PATH "$_default_out" "overrides.yaml path (Enter to accept default)"
  local out="$OVERRIDES_YAML_PATH"

  info "Generate minimal overrides via wizard (g), open \$EDITOR (e), or skip (s)?"
  prompt OVERRIDES_WIZARD_MODE "g" "g=wizard e=editor s=skip"
  local _mode="${OVERRIDES_WIZARD_MODE:-g}"
  if [[ "$_mode" == "s" ]]; then
    warn "Skipping file generation."
    return 0
  fi
  if [[ "$_mode" == "e" ]]; then
    "${EDITOR:-vi}" "$out"
    return 0
  fi

  if [[ "$AUTH_MODE" == "json" ]]; then
    write_overrides_json_stub "$out"
  elif [[ "$AUTH_MODE" == "wif_other" ]]; then
    write_overrides_wif_nonprod "$out"
  elif [[ "$INSTALL_PROFILE" == "prod" ]]; then
    write_overrides_prod_secrets "$out"
  else
    write_overrides_nonprod_secrets "$out"
  fi
  success "Wrote: $out — validate against Apigee Hybrid v1.16 configuration reference before helm install."
}

api_host() {
  if [[ "$DATA_RESIDENCY" == "y" ]]; then
    echo "https://${CONTROL_PLANE_LOCATION}-apigee.googleapis.com"
  else
    echo "https://apigee.googleapis.com"
  fi
}

step_control_plane_access() {
  section "Step 8 — Enable control plane access (Apigee API)" "" cyan
  prompt ORG_NAME "${ORG_NAME:-$PROJECT_ID}"
  if [[ "$DATA_RESIDENCY" != "y" ]]; then
    if confirm "Use data residency regional endpoint for this call?" "n"; then
      DATA_RESIDENCY="y"
      prompt CONTROL_PLANE_LOCATION "" "Control plane region slug"
    fi
  fi

  run_cmd export TOKEN="$(gcloud auth print-access-token)"

  local api base
  base="$(api_host)"
  api="${base}/v1/organizations/${ORG_NAME}/controlPlaneAccess"

  if [[ "$INSTALL_PROFILE" == "prod" ]]; then
    local sync_json pub_json
    # Service account emails match GCP project IDs from create-service-account (not Apigee org slug).
    sync_json="$(jq -nc \
      --arg s "serviceAccount:apigee-synchronizer@${PROJECT_ID}.iam.gserviceaccount.com" \
      '{synchronizer_identities:[$s]}')"
    if [[ "$MONETIZATION" == "y" ]]; then
      pub_json="$(jq -nc \
        --arg m "serviceAccount:apigee-mart@${PROJECT_ID}.iam.gserviceaccount.com" \
        --arg r "serviceAccount:apigee-runtime@${PROJECT_ID}.iam.gserviceaccount.com" \
        --arg t "serviceAccount:apigee-mint-task-scheduler@${PROJECT_ID}.iam.gserviceaccount.com" \
        '{analytics_publisher_identities:[$m,$r,$t]}')"
    else
      pub_json="$(jq -nc \
        --arg m "serviceAccount:apigee-mart@${PROJECT_ID}.iam.gserviceaccount.com" \
        --arg r "serviceAccount:apigee-runtime@${PROJECT_ID}.iam.gserviceaccount.com" \
        '{analytics_publisher_identities:[$m,$r]}')"
    fi
    info "Synchronizer payload: $sync_json"
    if confirm "PATCH synchronizer identities?" "y"; then
      run_cmd curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "${api}?update_mask=synchronizer_identities" -d "$sync_json"
    fi
    info "Analytics publisher payload: $pub_json"
    if confirm "PATCH analytics publisher identities?" "y"; then
      run_cmd curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "${api}?update_mask=analytics_publisher_identities" -d "$pub_json"
    fi
  else
    local np np_email
    np_email="serviceAccount:apigee-non-prod@${PROJECT_ID}.iam.gserviceaccount.com"
    np="$(jq -nc --arg s "$np_email" '{synchronizer_identities:[$s]}')"
    local pub
    pub="$(jq -nc --arg s "$np_email" '{analytics_publisher_identities:[$s]}')"
    info "Non-prod uses a single GSA for runtime roles: $np_email"
    if confirm "PATCH synchronizer identities (non-prod)?" "y"; then
      run_cmd curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "${api}?update_mask=synchronizer_identities" -d "$np"
    fi
    if confirm "PATCH analytics publisher identities (non-prod)?" "y"; then
      run_cmd curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "${api}?update_mask=analytics_publisher_identities" -d "$pub"
    fi
  fi

  if confirm "GET controlPlaneAccess (verify)?" "y"; then
    run_cmd curl -sS -H "Authorization: Bearer ${TOKEN}" "${api}"
    echo ""
  fi
}

step_cert_manager() {
  section "Step 9 — Install cert-manager ${CERT_MANAGER_VERSION}" "" cyan
  if skip_step "Skip cert-manager install?"; then
    return 0
  fi
  run_cmd kubectl apply -f "$CERT_MANAGER_URL"
  run_cmd kubectl get all -n cert-manager -o wide
}

step_crds() {
  section "Step 10 — Install Apigee hybrid CRDs" "" cyan
  if [[ ! -d "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/crds/default" ]]; then
    die "CRD path missing — check chart layout under $APIGEE_HELM_CHARTS_HOME"
  fi
  if confirm "Edit kustomization namespace to match ${APIGEE_NAMESPACE} (opens vi)?" "n"; then
    "${EDITOR:-vi}" "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/crds/default/kustomization.yaml"
  fi
  (
    cd "$APIGEE_HELM_CHARTS_HOME"
    if confirm "Run kubectl apply dry-run (server) for CRDs?" "y"; then
      run_cmd kubectl apply -k apigee-operator/etc/crds/default/ \
        --server-side --force-conflicts --validate=false --dry-run=server
    fi
    if confirm "Apply Apigee CRDs?" "y"; then
      run_cmd kubectl apply -k apigee-operator/etc/crds/default/ \
        --server-side --force-conflicts --validate=false
    fi
    run_cmd bash -c 'kubectl get crds | grep apigee || true'
  )
}

step_helm_install() {
  section "Step 11 — Install hybrid runtime with Helm" "" cyan
  local overrides="$APIGEE_HELM_CHARTS_HOME/overrides.yaml"
  if [[ ! -f "$overrides" ]]; then
    error "Missing $overrides — complete Step 7 first."
    return 1
  fi

  if confirm "Add --dry-run=server to each helm upgrade?" "n"; then
    DRY_RUN_HELM="y"
  fi
  local extra=()
  [[ "$DRY_RUN_HELM" == "y" ]] && extra+=(--dry-run=server)

  (
    cd "$APIGEE_HELM_CHARTS_HOME"
    run_cmd helm upgrade operator apigee-operator/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get deploy apigee-controller-manager || true

    run_cmd helm upgrade datastore apigee-datastore/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get apigeedatastore default || true

    run_cmd helm upgrade telemetry apigee-telemetry/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get apigeetelemetry apigee-telemetry || true

    run_cmd helm upgrade redis apigee-redis/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get apigeeredis default || true

    run_cmd helm upgrade ingress-manager apigee-ingress-manager/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get deployment apigee-ingressgateway-manager || true

    run_cmd helm upgrade "$ORG_NAME" apigee-org/ --install --namespace "$APIGEE_NAMESPACE" --atomic -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get apigeeorg || true

    prompt APIGEE_ENVIRONMENT_NAME "" "Apigee environment name for apigee-env chart"
    prompt HELM_ENV_RELEASE "${APIGEE_ENVIRONMENT_NAME}" "Helm release name for apigee-env"
    local env_name="$APIGEE_ENVIRONMENT_NAME"
    local env_release="${HELM_ENV_RELEASE:-$APIGEE_ENVIRONMENT_NAME}"
    run_cmd helm upgrade "$env_release" apigee-env/ --install --namespace "$APIGEE_NAMESPACE" --atomic --set "env=${env_name}" -f "$overrides" "${extra[@]}"
    run_cmd kubectl -n "$APIGEE_NAMESPACE" get apigeeenvironment || true
  )
}

usage() {
  cat <<EOF
apigee-hybrid-aks-setup.sh v${SCRIPT_VERSION}

Usage:
  $0 [--from-env] [step]

Steps:
  all | prereq | charts | namespace | serviceaccounts | secrets | tls | overrides | controlplane | certmanager | crds | helm

Docker / environment:
  Pass configuration with docker run -e KEY=value and/or --env-file FILE. Those variables are
  visible to this script without any flag.

  --from-env   Source the first existing file: /workspace/.env, ./apigee-hybrid.env, ~/.apigee-hybrid.env
               (in addition to variables already injected by Docker).

  APIGEE_SETUP_NONINTERACTIVE=1   Skip interactive prompts: use env values or prompt defaults; confirm()
                                    uses each prompt's default (y/n). Required values must be set or
                                    defaulted — missing values exit with an error.

  SKIP_GCLOUD_SDK_ENSURE=1        Do not auto-install Google Cloud SDK when gcloud is missing (default: install).

  SKIP_HTTPIE_ENSURE=1            Do not auto-install HTTPie (pip --user) when http is missing (default: install).

Common variables (see docs/setup-script-environment.md for the full list):
  APIGEE_HELM_CHARTS_HOME   Default: /workspace/apigee-hybrid/helm-charts
  CHART_REPO, CHART_VERSION, CERT_MANAGER_VERSION
  APIGEE_NAMESPACE, PROJECT_ID, ORG_NAME, CLUSTER_NAME, CLUSTER_LOCATION
  AZURE_RESOURCE_GROUP, AZURE_SUBSCRIPTION, INSTALL_PROFILE, AUTH_MODE, AUTH_MODE_CHOICE
  TLS_DOMAIN, TLS_ENV_GROUP
  INSTANCE_ID, ANALYTICS_REGION, INGRESS_GATEWAY_NAME, VIRTUALHOST_NAME, APIGEE_ENVIRONMENT_NAME
  SSL_CERT_PATH, SSL_KEY_PATH, CASSANDRA_HOST_NETWORK, GSA_EMAIL
  OVERRIDES_YAML_PATH, OVERRIDES_WIZARD_MODE, HELM_ENV_RELEASE

EOF
}

main() {
  local start_step="all"
  local use_env="n"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --from-env) use_env="y"; shift ;;
      *) start_step="$1"; shift ;;
    esac
  done

  header "Apigee Hybrid AKS" "Interactive setup v${SCRIPT_VERSION}" cyan

  if [[ "$use_env" == "y" ]]; then
    load_optional_env
  fi

  ensure_google_cloud_sdk
  ensure_httpie
  require_tools

  case "$start_step" in
    all)
      step_prerequisites
      step_optional_chart_pull
      step_create_namespace
      step_create_service_accounts
      step_k8s_secrets
      step_tls_certs
      step_overrides
      step_control_plane_access
      step_cert_manager
      step_crds
      step_helm_install
      ;;
    prereq) step_prerequisites ;;
    charts) step_optional_chart_pull ;;
    namespace) step_create_namespace ;;
    serviceaccounts) ensure_create_sa_tool; step_create_service_accounts ;;
    secrets) step_k8s_secrets ;;
    tls) step_tls_certs ;;
    overrides) step_overrides ;;
    controlplane) step_control_plane_access ;;
    certmanager) step_cert_manager ;;
    crds) step_crds ;;
    helm) step_helm_install ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"

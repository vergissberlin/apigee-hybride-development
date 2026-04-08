#!/usr/bin/env bash
# Interactive walkthrough for Apigee Hybrid v1.16 on Azure AKS (official steps 3–11).
# Docs: https://cloud.google.com/apigee/docs/hybrid/v1.16/
#
# Step 2 (download Helm charts) is pre-done in the container image; optional re-pull available.

set -euo pipefail

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

load_optional_env() {
  local f
  for f in /workspace/.env ./apigee-hybrid.env "${HOME}/.apigee-hybrid.env"; do
    if [[ -f "$f" ]]; then
      # shellcheck source=/dev/null
      set -a
      source "$f"
      set +a
      echo "Loaded environment from: $f"
      return 0
    fi
  done
  return 0
}

section() {
  echo ""
  echo "================================================================================"
  echo " $*"
  echo "================================================================================"
}

prompt() {
  local var_name="$1"
  local default="${2:-}"
  local hint="${3:-}"
  local current="${!var_name-}"
  local use="${current:-$default}"
  local input
  if [[ -n "$hint" ]]; then
    read -r -p "${var_name} [${use}] (${hint}): " input || true
  else
    read -r -p "${var_name} [${use}]: " input || true
  fi
  if [[ -n "$input" ]]; then
    printf -v "$var_name" '%s' "$input"
  elif [[ -z "${!var_name+x}" || -z "${!var_name}" ]]; then
    printf -v "$var_name" '%s' "$default"
  fi
}

confirm() {
  local msg="$1"
  local default="${2:-n}"
  local yn_hint="y/N"
  [[ "$default" == "y" ]] && yn_hint="Y/n"
  read -r -p "$msg [$yn_hint]: " reply || true
  reply="${reply:-}"
  if [[ -z "$reply" ]]; then
    [[ "$default" == "y" ]]
    return $?
  fi
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

run_cmd() {
  printf '+ %s\n' "$*" >&2
  "$@"
}

skip_step() {
  local msg="$1"
  if confirm "$msg" "n"; then
    return 0
  fi
  return 1
}

require_tools() {
  local missing=()
  command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")
  command -v helm >/dev/null 2>&1 || missing+=("helm")
  command -v gcloud >/dev/null 2>&1 || missing+=("gcloud")
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v az >/dev/null 2>&1 || missing+=("az")
  if ((${#missing[@]})); then
    echo "Missing tools: ${missing[*]}"
    exit 1
  fi
}

step_prerequisites() {
  section "Step 0 — Prerequisites (AKS + Google Cloud)"
  echo "Official reference: install-before-begin, provisioning, and AKS cluster access."
  echo "Helm charts (Step 2) are already present in the image under APIGEE_HELM_CHARTS_HOME unless you re-pull."
  echo ""

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
    local sub=""
    read -r -p "Subscription ID or name: " sub || true
    [[ -n "$sub" ]] && run_cmd az account set --subscription "$sub"
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
  section "Step 2 (optional) — Re-download Helm charts (OCI)"
  echo "Image build already pulled charts into: $APIGEE_HELM_CHARTS_HOME"
  if [[ -z "$CHART_VERSION" ]]; then
    read -r -p "CHART_VERSION to pull (empty = skip re-pull): " CHART_VERSION || true
  fi
  if [[ -z "${CHART_VERSION:-}" ]]; then
    echo "Skipping chart pull."
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
  section "Step 3 — Create the Apigee namespace"
  prompt APIGEE_NAMESPACE "apigee" "Kubernetes namespace for hybrid runtime"
  if kubectl get namespace "$APIGEE_NAMESPACE" >/dev/null 2>&1; then
    echo "Namespace '$APIGEE_NAMESPACE' already exists."
  else
    if confirm "Create namespace '$APIGEE_NAMESPACE'?" "y"; then
      run_cmd kubectl create namespace "$APIGEE_NAMESPACE"
    fi
  fi
}

ensure_create_sa_tool() {
  local tool="$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/tools/create-service-account"
  if [[ ! -f "$tool" ]]; then
    echo "ERROR: create-service-account not found at: $tool"
    exit 1
  fi
  if [[ ! -x "$tool" ]]; then
    run_cmd chmod +x "$tool"
  fi
}

step_create_service_accounts() {
  section "Step 4 — Create Google service accounts (create-service-account)"
  ensure_create_sa_tool
  echo "Choose installation profile (see Apigee docs: production vs non-production)."
  read -r -p "Profile [non-prod|prod] [non-prod]: " INSTALL_PROFILE || true
  INSTALL_PROFILE="${INSTALL_PROFILE:-non-prod}"
  if [[ "$INSTALL_PROFILE" != "prod" && "$INSTALL_PROFILE" != "non-prod" ]]; then
    echo "Invalid profile; defaulting to non-prod."
    INSTALL_PROFILE="non-prod"
  fi

  prompt PROJECT_ID "$PROJECT_ID" "GCP project ID"

  echo ""
  echo "Authentication method for hybrid (Step 5 preview — choose how keys are consumed):"
  echo "  1) Kubernetes Secrets (recommended for guided install)"
  echo "  2) JSON key files inside each Helm chart directory"
  echo "  3) Vault (manual — see official docs only)"
  echo "  4) Workload Identity Federation for GKE (not applicable on AKS — documentation only)"
  echo "  5) Workload Identity Federation on other platforms (AKS OIDC — advanced)"
  read -r -p "Choice [1]: " _am || true
  _am="${_am:-1}"
  case "$_am" in
    1) AUTH_MODE="secrets" ;;
    2) AUTH_MODE="json" ;;
    3) AUTH_MODE="vault" ;;
    4) AUTH_MODE="wif_gke" ;;
    5) AUTH_MODE="wif_other" ;;
    *) AUTH_MODE="secrets" ;;
  esac

  if [[ "$AUTH_MODE" == "vault" ]]; then
    echo "Vault path is not automated here. Complete Step 4–5 using:"
    echo "https://cloud.google.com/apigee/docs/hybrid/v1.16/install-service-accounts"
    echo "https://cloud.google.com/apigee/docs/hybrid/v1.16/install-sa-authentication"
    confirm "Continue after you have finished Vault setup externally?" "n" || exit 0
    return 0
  fi

  if [[ "$AUTH_MODE" == "wif_gke" ]]; then
    echo "Skipping execution: WIF for GKE is for Google Kubernetes Engine only."
    echo "On AKS use option 5 (WIF other) or Kubernetes Secrets / JSON files."
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
        echo "ERROR: expected *-apigee-non-prod.json under apigee-datastore"
        exit 1
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
  section "Step 5 — Kubernetes Secrets for service accounts"
  if [[ "$AUTH_MODE" != "secrets" ]]; then
    echo "AUTH_MODE=$AUTH_MODE — skipping kubectl secret creation (not using Kubernetes Secrets path)."
    if [[ "$AUTH_MODE" == "json" ]]; then
      echo "JSON file auth: no extra Step 5 actions (see docs). Proceed to TLS / overrides."
    elif [[ "$AUTH_MODE" == "wif_other" ]]; then
      step_wif_other_guidance
    fi
    return 0
  fi

  prompt APIGEE_NAMESPACE "${APIGEE_NAMESPACE:-apigee}"
  prompt PROJECT_ID "$PROJECT_ID"

  if [[ "$INSTALL_PROFILE" == "prod" ]]; then
    local base="$APIGEE_HELM_CHARTS_HOME/service-accounts"
    run_cmd kubectl create secret generic apigee-logger-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-logger.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-guardrails-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-guardrails.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-metrics-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-metrics.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-watcher-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-watcher.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-mart-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-mart.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-synchronizer-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-synchronizer.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    run_cmd kubectl create secret generic apigee-runtime-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-runtime.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    if [[ "$MONETIZATION" == "y" ]] || confirm "Create apigee-mint-task-scheduler-svc-account secret (Monetization)?" "n"; then
      run_cmd kubectl create secret generic apigee-mint-task-scheduler-svc-account \
        --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-mint-task-scheduler.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    fi
  else
    local base="$APIGEE_HELM_CHARTS_HOME/service-accounts"
    run_cmd kubectl create secret generic apigee-non-prod-svc-account \
      --from-file="client_secret.json=$base/${PROJECT_ID}-apigee-non-prod.json" -n "$APIGEE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  fi
  echo "Optional: delete JSON files on disk after secrets exist (see official security guidance)."
}

step_wif_other_guidance() {
  section "Step 5 — Workload Identity Federation on other platforms (AKS)"
  echo "Follow: https://cloud.google.com/apigee/docs/hybrid/v1.16/install-sa-authentication (WIF on other platforms)"
  echo "Enable AKS OIDC issuer: https://learn.microsoft.com/azure/aks/use-oidc-issuer"
  echo ""
  if [[ -n "${AZURE_RESOURCE_GROUP:-}" && -n "${CLUSTER_NAME:-}" ]]; then
    if confirm "Print OIDC issuer URL via Azure CLI?" "y"; then
      run_cmd az aks show -n "$CLUSTER_NAME" -g "$AZURE_RESOURCE_GROUP" --query "oidcIssuerProfile.issuerUrl" -otsv
    fi
  else
    echo "Set AZURE_RESOURCE_GROUP and CLUSTER_NAME to query OIDC issuer, or run:"
    echo '  az aks show -n CLUSTER_NAME -g RESOURCE_GROUP --query "oidcIssuerProfile.issuerUrl" -otsv'
  fi
  echo ""
  echo "Enable STS API if needed:"
  echo "  gcloud services enable sts.googleapis.com --project $PROJECT_ID"
  echo "Then create workload identity pool/provider and IAM bindings per Google documentation."
}

step_tls_certs() {
  section "Step 6 — TLS certificates (self-signed quickstart)"
  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl not found. Install openssl in the image or on the host."
    exit 1
  fi
  local domain env_group
  read -r -p "DOMAIN (hostname for environment group, CN=): " domain || true
  read -r -p "ENV_GROUP name (used in cert filenames): " env_group || true
  if [[ -z "$domain" || -z "$env_group" ]]; then
    echo "DOMAIN and ENV_GROUP are required."
    return 1
  fi
  local cert_dir="$APIGEE_HELM_CHARTS_HOME/apigee-virtualhost/certs"
  run_cmd mkdir -p "$cert_dir"
  run_cmd openssl req -nodes -new -x509 \
    -keyout "$cert_dir/keystore_${env_group}.key" \
    -out "$cert_dir/keystore_${env_group}.pem" \
    -subj "/CN=${domain}" -days 3650
  run_cmd ls -la "$cert_dir"
  echo "Use these paths in overrides.yaml virtualhosts (sslCertPath / sslKeyPath)."
}

write_overrides_nonprod_secrets() {
  local out="$1"
  local instance_id analytics_region ingress_name env_group_name env_name
  read -r -p "instanceID (unique per cluster): " instance_id
  read -r -p "gcp.region (Analytics region): " analytics_region
  read -r -p "ingressGateways[0].name (max 17 chars, e.g. ingw1): " ingress_name
  read -r -p "virtualhosts[0].name (environment group name): " env_group_name
  read -r -p "envs[0].name (Apigee environment name): " env_name
  local cert_pem cert_key cassandra_host_net
  read -r -p "sslCertPath (e.g. apigee-virtualhost/certs/keystore_${env_group_name}.pem): " cert_pem
  read -r -p "sslKeyPath (e.g. apigee-virtualhost/certs/keystore_${env_group_name}.key): " cert_key
  read -r -p "cassandra.hostNetwork [true|false] (AKS multi-region/no cross-cluster pod comm often true): " cassandra_host_net
  [[ -z "$cassandra_host_net" ]] && cassandra_host_net="false"

  local contract_line=""
  if [[ "$DATA_RESIDENCY" == "y" ]]; then
    prompt CONTROL_PLANE_LOCATION "$CONTROL_PLANE_LOCATION" "Control plane region slug"
    contract_line="contractProvider: https://${CONTROL_PLANE_LOCATION}-apigee.googleapis.com"
  fi

  cat >"$out" <<EOF
# Generated by apigee-hybrid-aks-setup.sh — review against official docs:
# https://cloud.google.com/apigee/docs/hybrid/v1.16/install-create-overrides

instanceID: "${instance_id}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${analytics_region}

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true
${contract_line}

envs:
  - name: ${env_name}
    serviceAccountSecretRefs:
      synchronizer: apigee-non-prod-svc-account
      runtime: apigee-non-prod-svc-account

cassandra:
  hostNetwork: ${cassandra_host_net}
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
  - name: ${ingress_name}
    replicaCountMin: 1
    replicaCountMax: 3

virtualhosts:
  - name: ${env_group_name}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${ingress_name}
    sslCertPath: ${cert_pem}
    sslKeyPath: ${cert_key}

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
  local instance_id analytics_region ingress_name env_group_name env_name
  read -r -p "instanceID: " instance_id
  read -r -p "gcp.region (Analytics region): " analytics_region
  read -r -p "ingressGateways[0].name: " ingress_name
  read -r -p "virtualhosts[0].name (environment group): " env_group_name
  read -r -p "envs[0].name (environment): " env_name
  local cert_pem cert_key cassandra_host_net
  read -r -p "sslCertPath: " cert_pem
  read -r -p "sslKeyPath: " cert_key
  read -r -p "cassandra.hostNetwork [true|false]: " cassandra_host_net
  [[ -z "$cassandra_host_net" ]] && cassandra_host_net="false"

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

instanceID: "${instance_id}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${analytics_region}

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true
${contract_line}

envs:
  - name: ${env_name}
    serviceAccountSecretRefs:
      synchronizer: apigee-synchronizer-svc-account
      runtime: apigee-runtime-svc-account

cassandra:
  hostNetwork: ${cassandra_host_net}
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
  - name: ${ingress_name}
    replicaCountMin: 2
    replicaCountMax: 10

virtualhosts:
  - name: ${env_group_name}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${ingress_name}
    sslCertPath: ${cert_pem}
    sslKeyPath: ${cert_key}

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
  local gsa_email pool_id provider_id
  read -r -p "gcp.workloadIdentity.gsa (apigee-non-prod@PROJECT.iam.gserviceaccount.com): " gsa_email
  read -r -p "instanceID: " instance_id
  read -r -p "gcp.region (Analytics): " analytics_region
  read -r -p "ingressGateways[0].name: " ingress_name
  read -r -p "virtualhosts[0].name: " env_group_name
  read -r -p "envs[0].name: " env_name
  read -r -p "sslCertPath: " cert_pem
  read -r -p "sslKeyPath: " cert_key
  read -r -p "cassandra.hostNetwork [true|false]: " cassandra_host_net
  [[ -z "$cassandra_host_net" ]] && cassandra_host_net="false"

  cat >"$out" <<EOF
# WIF on other platforms — fill workloadIdentity details per docs (pool/provider IDs, etc.)

instanceID: "${instance_id}"
namespace: ${APIGEE_NAMESPACE}

gcp:
  projectID: ${PROJECT_ID}
  region: ${analytics_region}
  workloadIdentity:
    enabled: true
    gsa: "${gsa_email}"

k8sCluster:
  name: ${CLUSTER_NAME}
  region: ${CLUSTER_LOCATION}

org: ${ORG_NAME}

enhanceProxyLimits: true

envs:
  - name: ${env_name}

cassandra:
  hostNetwork: ${cassandra_host_net}
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
  - name: ${ingress_name}
    replicaCountMin: 1
    replicaCountMax: 3

virtualhosts:
  - name: ${env_group_name}
    selector:
      app: apigee-ingressgateway
      ingress_name: ${ingress_name}
    sslCertPath: ${cert_pem}
    sslKeyPath: ${cert_key}
EOF
}

step_overrides() {
  section "Step 7 — overrides.yaml"
  if confirm "Set data residency / regional control plane (contractProvider)?" "n"; then
    DATA_RESIDENCY="y"
    prompt CONTROL_PLANE_LOCATION "" "e.g. europe-west1"
  else
    DATA_RESIDENCY="n"
  fi

  local out="$APIGEE_HELM_CHARTS_HOME/overrides.yaml"
  echo "Default output path: $out"
  read -r -p "Press Enter to accept or type alternate path: " _op || true
  [[ -n "${_op:-}" ]] && out="$_op"

  echo "Generate minimal overrides via wizard (g), open \$EDITOR (e), or skip (s)?"
  read -r -p "[g/e/s] [g]: " _mode || true
  _mode="${_mode:-g}"
  if [[ "$_mode" == "s" ]]; then
    echo "Skipping file generation."
    return 0
  fi
  if [[ "$_mode" == "e" ]]; then
    "${EDITOR:-vi}" "$out"
    return 0
  fi

  if [[ "$AUTH_MODE" == "wif_other" ]]; then
    write_overrides_wif_nonprod "$out"
  elif [[ "$INSTALL_PROFILE" == "prod" ]]; then
    write_overrides_prod_secrets "$out"
  else
    write_overrides_nonprod_secrets "$out"
  fi
  echo "Wrote: $out — validate against Apigee Hybrid v1.16 configuration reference before helm install."
}

api_host() {
  if [[ "$DATA_RESIDENCY" == "y" ]]; then
    echo "https://${CONTROL_PLANE_LOCATION}-apigee.googleapis.com"
  else
    echo "https://apigee.googleapis.com"
  fi
}

step_control_plane_access() {
  section "Step 8 — Enable control plane access (Apigee API)"
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
    sync_json="$(jq -nc \
      --arg s "serviceAccount:apigee-synchronizer@${ORG_NAME}.iam.gserviceaccount.com" \
      '{synchronizer_identities:[$s]}')"
    if [[ "$MONETIZATION" == "y" ]]; then
      pub_json="$(jq -nc \
        --arg m "serviceAccount:apigee-mart@${ORG_NAME}.iam.gserviceaccount.com" \
        --arg r "serviceAccount:apigee-runtime@${ORG_NAME}.iam.gserviceaccount.com" \
        --arg t "serviceAccount:apigee-mint-task-scheduler@${ORG_NAME}.iam.gserviceaccount.com" \
        '{analytics_publisher_identities:[$m,$r,$t]}')"
    else
      pub_json="$(jq -nc \
        --arg m "serviceAccount:apigee-mart@${ORG_NAME}.iam.gserviceaccount.com" \
        --arg r "serviceAccount:apigee-runtime@${ORG_NAME}.iam.gserviceaccount.com" \
        '{analytics_publisher_identities:[$m,$r]}')"
    fi
    echo "Synchronizer payload: $sync_json"
    if confirm "PATCH synchronizer identities?" "y"; then
      run_cmd curl -sS -X PATCH -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
        "${api}?update_mask=synchronizer_identities" -d "$sync_json"
    fi
    echo "Analytics publisher payload: $pub_json"
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
    echo "Non-prod uses a single GSA for runtime roles: $np_email"
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
  section "Step 9 — Install cert-manager ${CERT_MANAGER_VERSION}"
  if skip_step "Skip cert-manager install?"; then
    return 0
  fi
  run_cmd kubectl apply -f "$CERT_MANAGER_URL"
  run_cmd kubectl get all -n cert-manager -o wide
}

step_crds() {
  section "Step 10 — Install Apigee hybrid CRDs"
  if [[ ! -d "$APIGEE_HELM_CHARTS_HOME/apigee-operator/etc/crds/default" ]]; then
    echo "ERROR: CRD path missing — check chart layout under $APIGEE_HELM_CHARTS_HOME"
    exit 1
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
    run_cmd kubectl get crds \| grep apigee || true
  )
}

step_helm_install() {
  section "Step 11 — Install hybrid runtime with Helm"
  local overrides="$APIGEE_HELM_CHARTS_HOME/overrides.yaml"
  [[ -f "$overrides" ]] || { echo "Missing $overrides — complete Step 7 first."; return 1; }

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

    local env_name env_release
    read -r -p "Apigee environment name for apigee-env chart: " env_name
    read -r -p "Helm release name for apigee-env [same as env]: " env_release
    env_release="${env_release:-$env_name}"
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

Environment (optional):
  APIGEE_HELM_CHARTS_HOME  Default: /workspace/apigee-hybrid/helm-charts
  Optional file: /workspace/.env, ./apigee-hybrid.env — sourced when --from-env is passed

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

  echo "Apigee Hybrid AKS interactive setup (v${SCRIPT_VERSION})"
  require_tools
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required for Step 8 JSON payloads."; exit 1; }

  if [[ "$use_env" == "y" ]]; then
    load_optional_env
  fi

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

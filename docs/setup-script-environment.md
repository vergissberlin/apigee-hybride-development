# Setup script environment variables

The [apigee-hybrid-aks-setup.sh](../scripts/apigee-hybrid-aks-setup.sh) script reads configuration from the process environment. You can pass values into the container with `docker run -e KEY=value`, `docker run --env-file .env`, or by mounting a file and using `--from-env` (see below).

## Non-interactive mode

Set **`APIGEE_SETUP_NONINTERACTIVE=1`** to disable interactive prompts:

- **`prompt`**: uses the current value for each variable, or the default shown in the script if unset. If a required value is still empty, the script exits with an error.
- **`confirm`**: uses the documented default (`y` or `n`) for each question without reading from the terminal.

Use this for automation or CI when all required variables are supplied.

## `--from-env` vs Docker environment

- **`docker run -e` / `--env-file`**: variables are already in the shell environment when the script starts. You do **not** need `--from-env` for those.
- **`--from-env`**: loads the first existing file among `/workspace/.env`, `./apigee-hybrid.env`, and `$HOME/.apigee-hybrid.env` (`set -a` / `source`). Use this when you prefer a mounted env file instead of repeating `-e` flags.

A starting template with placeholders is in [`.env.example`](../.env.example) at the repository root: copy it to `.env` or `apigee-hybrid.env`, edit the values, and keep those files out of version control.

## Variable reference

| Variable | Description | Typical default / notes |
|----------|-------------|-------------------------|
| **General** | | |
| `APIGEE_SETUP_NONINTERACTIVE` | Set to `1` for non-interactive runs | unset (interactive) |
| `SKIP_GCLOUD_SDK_ENSURE` | Set to `1` to skip auto-install of the Google Cloud SDK when `gcloud` is missing | unset (script installs SDK if needed) |
| `APIGEE_HELM_CHARTS_HOME` | Helm charts directory | `/workspace/apigee-hybrid/helm-charts` |
| `CHART_REPO` | OCI chart repo URL | Apigee public OCI |
| `CHART_VERSION` | Chart version (optional re-pull in `charts` step) | image build default; empty skips re-pull |
| `CERT_MANAGER_VERSION` | cert-manager manifest version | `v1.19.2` |
| **Cluster / org** | | |
| `APIGEE_NAMESPACE` | Kubernetes namespace | `apigee` |
| `PROJECT_ID` | GCP project ID | — |
| `ORG_NAME` | Apigee org name | often same as `PROJECT_ID` |
| `CLUSTER_NAME` | AKS cluster name | — |
| `CLUSTER_LOCATION` | Azure region (e.g. `westeurope`) | — |
| `AZURE_RESOURCE_GROUP` | AKS resource group | — |
| `AZURE_SUBSCRIPTION` | Azure subscription ID or name (when you confirm subscription step) | — |
| `INSTALL_PROFILE` | `non-prod` or `prod` | `non-prod` |
| `AUTH_MODE` | `secrets`, `json`, `vault`, `wif_gke`, `wif_other` | if unset, menu or `AUTH_MODE_CHOICE` |
| `AUTH_MODE_CHOICE` | Menu `1`–`5` when `AUTH_MODE` unset | `1` = secrets |
| `DATA_RESIDENCY` | `y` / `n` (regional control plane) | set in overrides step via confirm |
| `CONTROL_PLANE_LOCATION` | Region slug for data residency API | when `DATA_RESIDENCY=y` |
| `MONETIZATION` | prod monetization service accounts | `n` |
| `DRY_RUN_HELM` | `y` for `helm upgrade --dry-run=server` | `n` |
| **TLS (step `tls`)** | | |
| `TLS_DOMAIN` | Certificate CN / hostname | — |
| `TLS_ENV_GROUP` | Filename slug (`keystore_<name>.*`) | — |
| **Overrides wizard (step `overrides`)** | | |
| `OVERRIDES_YAML_PATH` | Output path for `overrides.yaml` | `$APIGEE_HELM_CHARTS_HOME/overrides.yaml` |
| `OVERRIDES_WIZARD_MODE` | `g` = generate, `e` = editor, `s` = skip | `g` |
| `INSTANCE_ID` | Hybrid instance ID | — |
| `ANALYTICS_REGION` | `gcp.region` (Analytics) | — |
| `INGRESS_GATEWAY_NAME` | Ingress gateway name (≤17 chars) | `ingw1` |
| `VIRTUALHOST_NAME` | Virtual host / env group name | — |
| `APIGEE_ENVIRONMENT_NAME` | Apigee environment name | — |
| `SSL_CERT_PATH` | Path under chart dir (e.g. virtualhost certs) | — |
| `SSL_KEY_PATH` | Key path | — |
| `CASSANDRA_HOST_NETWORK` | `true` or `false` | `false` |
| `GSA_EMAIL` | Workload Identity GSA email (WIF non-prod path) | — |
| **Helm step `helm`** | | |
| `HELM_ENV_RELEASE` | Helm release name for `apigee-env` | defaults to `APIGEE_ENVIRONMENT_NAME` |

Boolean-style `confirm` steps (login, `kubectl`, PATCH calls, etc.) follow their **default** when `APIGEE_SETUP_NONINTERACTIVE=1` (see script source for each default).

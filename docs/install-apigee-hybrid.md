# Apigee Hybrid Installation Guide

This guide walks you through installing Apigee Hybrid v1.16 on Azure Kubernetes Service (AKS).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Interactive setup script](#interactive-setup-script)
3. [Before You Begin](#before-you-begin)
4. [Download Helm Charts](#download-helm-charts)
5. [Create Namespace](#create-namespace)
6. [Configure Apigee Hybrid](#configure-apigee-hybrid)
7. [Verify Installation](#verify-installation)

---

## Prerequisites

All required tools are included in this Docker image:

| Tool | Purpose |
|------|---------|
| `gcloud` | Google Cloud CLI for managing Apigee and GCP resources |
| `az` | Azure CLI for managing AKS clusters |
| `kubectl` | Kubernetes CLI for interacting with the cluster |
| `helm` | Kubernetes package manager for deploying Apigee Hybrid charts |
| `httpie` | HTTP client for testing APIs |

The published image is **`linux/amd64`**. On **Apple Silicon**, add **`--platform linux/amd64`** to `docker pull` / `docker run` (or use the repo **`justfile`**).

If you want to run the **same image inside a Kubernetes cluster** (Job/Pod) with mounts and environment variables for GCP and Azure, see [run-in-kubernetes.md](run-in-kubernetes.md).

### Testing the setup script (local / CI)

Smoke and non-interactive `prereq` checks run in Docker on **`linux/amd64`** (aligned with Azure Cloud Shell **x86_64** userspace). They do not replace a manual sanity check in **Azure Cloud Shell** when you change authentication or cluster steps. See [CONTRIBUTING.md](../CONTRIBUTING.md#setup-script-tests-local-and-ci) and [`docs/setup-script-environment.md`](setup-script-environment.md) (`SKIP_AZ_GET_CREDENTIALS`, `SKIP_KUBECTL_CLUSTER_CHECK`).

Start the development container:

```bash
docker run -it --rm --platform linux/amd64 \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  vergissberlin/apigee-hybride-development:latest
```

---

## Interactive setup script

For an interactive walkthrough aligned with the official Apigee Hybrid v1.16 documentation (steps 3–11: namespace through Helm installs), use the Bash script shipped in the image:

```bash
bash /workspace/scripts/apigee-hybrid-aks-setup.sh
```

The script loads [scripts/misc-cli-utils.sh](../scripts/misc-cli-utils.sh) for consistent terminal output (section headers, prompts, and command echoing).

**Environment variables:** you can pass configuration with `docker run -e KEY=value`, `docker run --env-file .env`, or both. Injected variables are available to the script **without** any extra flag. The full list and non-interactive behaviour are documented in [setup-script-environment.md](setup-script-environment.md).

**`--from-env`** (optional): source a mounted env file from the first existing path among `/workspace/.env`, `./apigee-hybrid.env`, and `$HOME/.apigee-hybrid.env`. Use this when you prefer a file over many `-e` options:

```bash
docker run -it --rm --platform linux/amd64 \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  -v "$(pwd)/apigee-hybrid.env:/workspace/.env:ro" \
  vergissberlin/apigee-hybride-development:latest \
  bash /workspace/scripts/apigee-hybrid-aks-setup.sh --from-env
```

Example using **`--env-file`** and non-interactive mode (adjust variables to your project):

```bash
docker run -it --rm --platform linux/amd64 \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  --env-file apigee-hybrid.env \
  -e APIGEE_SETUP_NONINTERACTIVE=1 \
  vergissberlin/apigee-hybride-development:latest \
  apigee-hybrid-aks-setup prereq
```

Helm charts are **already downloaded** during the image build (see [Download Apigee Hybrid Charts](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts)); the script treats step 2 as done and can optionally re-pull a different `CHART_VERSION` if you set it.

Run a single phase (for example after fixing a failure) by passing a step name: `prereq`, `charts`, `namespace`, `serviceaccounts`, `secrets`, `tls`, `overrides`, `controlplane`, `certmanager`, `crds`, or `helm`. Use `bash /workspace/scripts/apigee-hybrid-aks-setup.sh --help` for details.

The script does **not** replace [Part 1 provisioning](https://cloud.google.com/apigee/docs/hybrid/v1.16/precog-enableapi) or cluster creation; complete those first, then use this tool for the runtime install on AKS.

---

## Before You Begin

### 1. Authenticate with Google Cloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Authenticate with Azure

```bash
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
```

### 3. Connect to your AKS cluster

```bash
az aks get-credentials \
  --resource-group YOUR_RESOURCE_GROUP \
  --name YOUR_AKS_CLUSTER_NAME
```

### 4. Verify cluster connectivity

```bash
kubectl cluster-info
kubectl get nodes
```

---

## Download Helm Charts

The Apigee Hybrid Helm chart repository is pre-configured in this image.

### Update the Helm repository

```bash
helm repo update
```

### List available Apigee Hybrid chart versions

```bash
helm search repo apigee
```

### Pull the Apigee Hybrid charts for a dev environment

```bash
# Set the Apigee Hybrid version
export APIGEE_HYBRID_VERSION=1.16.0

# Pull the charts
helm pull apigee/apigee-operator --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-datastore --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-env --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-ingress-manager --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-org --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-redis --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-telemetry --version "${APIGEE_HYBRID_VERSION}"
helm pull apigee/apigee-virtualhost --version "${APIGEE_HYBRID_VERSION}"
```

---

## Create Namespace

Apigee Hybrid requires dedicated Kubernetes namespaces.

### Create the Apigee system namespace

```bash
kubectl create namespace apigee-system
```

### Create the Apigee namespace

```bash
kubectl create namespace apigee
```

### Label the namespaces

```bash
kubectl label namespace apigee-system \
  apigee.cloud.google.com/envs=apigee-system

kubectl label namespace apigee \
  apigee.cloud.google.com/envs=apigee
```

### Verify the namespaces

```bash
kubectl get namespaces | grep apigee
```

Expected output:

```
apigee        Active   Xs
apigee-system Active   Xs
```

---

## Configure Apigee Hybrid

### Set environment variables

```bash
export PROJECT_ID=YOUR_PROJECT_ID
export APIGEE_ORG=YOUR_PROJECT_ID       # Usually the same as PROJECT_ID
export APIGEE_ENV=dev                   # Your Apigee environment name
export CLUSTER_NAME=YOUR_AKS_CLUSTER
export CLUSTER_REGION=YOUR_REGION       # e.g. europe-west1
```

### Create a service account for Apigee

```bash
gcloud iam service-accounts create apigee-hybrid \
  --display-name "Apigee Hybrid Service Account" \
  --project "${PROJECT_ID}"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:apigee-hybrid@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/apigee.runtimeAgent"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:apigee-hybrid@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role "roles/apigee.analyticsAgent"
```

### Create and download the service account key

```bash
gcloud iam service-accounts keys create ./apigee-hybrid-key.json \
  --iam-account "apigee-hybrid@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Create Kubernetes secret for the service account

```bash
kubectl create secret generic apigee-hybrid-key \
  --from-file=apigee-hybrid-key.json=./apigee-hybrid-key.json \
  --namespace apigee
```

### Install the Apigee Operator

```bash
helm upgrade apigee-operator apigee/apigee-operator \
  --install \
  --namespace apigee-system \
  --atomic \
  --set "gcp.projectID=${PROJECT_ID}"
```

### Install the Apigee Datastore

```bash
helm upgrade apigee-datastore apigee/apigee-datastore \
  --install \
  --namespace apigee \
  --atomic \
  --set "gcp.projectID=${PROJECT_ID}" \
  --set "gcp.region=${CLUSTER_REGION}"
```

### Install the Apigee Organization

```bash
helm upgrade apigee-org apigee/apigee-org \
  --install \
  --namespace apigee \
  --atomic \
  --set "gcp.projectID=${PROJECT_ID}" \
  --set "org=${APIGEE_ORG}"
```

### Install the Apigee Environment

```bash
helm upgrade apigee-env apigee/apigee-env \
  --install \
  --namespace apigee \
  --atomic \
  --set "env=${APIGEE_ENV}" \
  --set "gcp.projectID=${PROJECT_ID}"
```

---

## Verify Installation

### Check all pods are running

```bash
kubectl get pods --namespace apigee-system
kubectl get pods --namespace apigee
```

### Check Apigee components

```bash
kubectl get apigeedatastore,apigeeenvironment,apigeeorganization \
  --namespace apigee
```

### Test API connectivity with HTTPie

```bash
# Replace with your Apigee ingress IP or hostname
export APIGEE_HOST=YOUR_APIGEE_INGRESS_HOST

http GET "https://${APIGEE_HOST}/healthz" --verify=no
```

---

## Useful Commands

```bash
# View Apigee Hybrid Helm releases
helm list --namespace apigee
helm list --namespace apigee-system

# Watch pod startup
kubectl get pods --namespace apigee --watch

# View logs
kubectl logs -n apigee -l app=apigee-runtime --tail=100

# Upgrade Apigee Hybrid charts
helm repo update
helm upgrade apigee-operator apigee/apigee-operator --namespace apigee-system
```

---

## References

- [Apigee Hybrid v1.16 Documentation](https://cloud.google.com/apigee/docs/hybrid/v1.16/overview)
- [Install Apigee Hybrid – Before You Begin](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-before-begin)
- [Download Apigee Hybrid Charts](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts)
- [Create Namespace](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-create-namespace)
- [Azure AKS Documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [Helm Documentation](https://helm.sh/docs/)

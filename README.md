# apigee-hybride-development

Docker image for developing and configuring [Apigee Hybrid](https://cloud.google.com/apigee/docs/hybrid/v1.16/overview) on [Azure AKS](https://learn.microsoft.com/en-us/azure/aks/).

This repository is part of the [vergissberlin organization on GitHub](https://github.com/vergissberlin?tab=repositories). The image is **based on** [`vergissberlin/ubuntu-development:24.04`](https://hub.docker.com/r/vergissberlin/ubuntu-development) ([`ubuntu-development` source](https://github.com/vergissberlin/ubuntu-development)), so it inherits that base image’s general development tooling and **adds** the cloud and Apigee-specific CLIs listed below.

## Included Tools

| Tool                                                       | Description                                              |
|------------------------------------------------------------|----------------------------------------------------------|
| [`gcloud`](https://cloud.google.com/sdk/gcloud)            | Google Cloud CLI – manage Apigee and GCP resources       |
| [`az`](https://learn.microsoft.com/en-us/cli/azure/)       | Azure CLI – manage AKS clusters and Azure resources      |
| [`kubectl`](https://kubernetes.io/docs/reference/kubectl/) | Kubernetes CLI – interact with AKS clusters              |
| [`helm`](https://helm.sh/)                                 | Kubernetes package manager – deploy Apigee Hybrid charts |
| [`httpie`](https://httpie.io/)                             | HTTP client – test and debug APIs                        |

## Quick Start

Published images are **`linux/amd64`** (same as CI). On **Apple Silicon** (arm64), use **`--platform linux/amd64`** for `docker pull` and `docker run` so Docker pulls the correct manifest and runs the image (via emulation).

```bash
docker pull --platform linux/amd64 vergissberlin/apigee-hybride-development:latest

docker run -it --rm --platform linux/amd64 \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  vergissberlin/apigee-hybride-development:latest
```

If **`kubectl`** is already pointed at a cluster (for example after `az aks get-credentials`), you can open an **interactive shell** in a one-off Pod (RBAC, image pulls, and cloud credentials in-cluster are covered in [docs/run-in-kubernetes.md](docs/run-in-kubernetes.md)):

```bash
kubectl run -it --rm apigee-hybride-dev --restart=Never \
  --image=vergissberlin/apigee-hybride-development:latest \
  -- zsh
```

Or use [`just`](https://github.com/casey/just): `just pull` / `just run` (the repo `justfile` sets the platform for you).

You can pass setup configuration with **`docker run -e KEY=value`**, **`--env-file .env`**, or a mounted file plus **`apigee-hybrid-aks-setup --from-env`** (see [docs/setup-script-environment.md](docs/setup-script-environment.md)). Copy [`.env.example`](.env.example) to `.env` (or `apigee-hybrid.env`) and adjust placeholders. Set **`APIGEE_SETUP_NONINTERACTIVE=1`** to run without interactive prompts when all required variables are supplied.

## Running in Kubernetes

To run this image as a **Pod**, **Job**, or **CronJob** inside a cluster (with **Google Cloud** and **Azure** credentials via Secrets and env vars instead of laptop bind mounts), see **[docs/run-in-kubernetes.md](docs/run-in-kubernetes.md)**.

Maintainers: where images are published, CI triggers, and registry setup are documented in [CONTRIBUTING.md — Releases and CI](CONTRIBUTING.md#releases-and-ci).

**Local Docker builds** (platform, Apigee charts baked into the image, shells): [CONTRIBUTING.md — Build the image locally](CONTRIBUTING.md#build-the-image-locally).

## Installation Guide

For a full step-by-step guide to install Apigee Hybrid v1.16 on Azure AKS, see:

📖 **[docs/install-apigee-hybrid.md](docs/install-apigee-hybrid.md)**

The container image includes an **interactive setup script** at `/workspace/scripts/apigee-hybrid-aks-setup.sh` (also [scripts/apigee-hybrid-aks-setup.sh](scripts/apigee-hybrid-aks-setup.sh) in this repository). The same script is on `PATH` as `apigee-hybrid-aks-setup` (symlink in `/usr/bin`). It sources shared CLI helpers from [scripts/misc-cli-utils.sh](scripts/misc-cli-utils.sh) (colored banners, `info`/`warn`/`error`, `prompt`/`confirm`, `run_cmd`, etc.). It walks through Google’s official hybrid install steps **3–11** (namespace, service accounts, authentication, TLS, `overrides.yaml`, control-plane API access, cert-manager, CRDs, Helm installs), prompts for variables (or uses environment variables / defaults — see [docs/setup-script-environment.md](docs/setup-script-environment.md)), skips chart download when charts are already baked into the image, and highlights AKS-specific commands (for example `az aks get-credentials` and OIDC for Workload Identity Federation). Run `apigee-hybrid-aks-setup --help` (or `bash /workspace/scripts/apigee-hybrid-aks-setup.sh --help`) inside the container for usage and step names.

The guide covers:

1. **Before You Begin** – authenticate with GCP and Azure, connect to AKS
2. **Download Helm Charts** – pull the Apigee Hybrid Helm charts for a dev environment
3. **Create Namespace** – create and label the required Kubernetes namespaces
4. **Configure Apigee Hybrid** – deploy the Apigee operator, datastore, org, and environments
5. **Verify Installation** – confirm all components are running

## References

- [Apigee Hybrid v1.16 – Before You Begin](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-before-begin)
- [Apigee Hybrid v1.16 – Download Charts](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts)
- [Apigee Hybrid v1.16 – Create Namespace](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-create-namespace)

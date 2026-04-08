# apigee-hybride-development

Docker image for developing and configuring [Apigee Hybrid](https://cloud.google.com/apigee/docs/hybrid/v1.16/overview) on [Azure AKS](https://learn.microsoft.com/en-us/azure/aks/).

Based on [`vergissberlin/ubuntu-development:24.04`](https://hub.docker.com/r/vergissberlin/ubuntu-development).

## Included Tools

| Tool                                                       | Description                                              |
|------------------------------------------------------------|----------------------------------------------------------|
| [`gcloud`](https://cloud.google.com/sdk/gcloud)            | Google Cloud CLI – manage Apigee and GCP resources       |
| [`az`](https://learn.microsoft.com/en-us/cli/azure/)       | Azure CLI – manage AKS clusters and Azure resources      |
| [`kubectl`](https://kubernetes.io/docs/reference/kubectl/) | Kubernetes CLI – interact with AKS clusters              |
| [`helm`](https://helm.sh/)                                 | Kubernetes package manager – deploy Apigee Hybrid charts |
| [`httpie`](https://httpie.io/)                             | HTTP client – test and debug APIs                        |

## Quick Start

```bash
docker pull vergissberlin/apigee-hybrid-development:latest

docker run -it --rm \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  vergissberlin/apigee-hybrid-development:latest
```

## CI / published images

Pushes to `main`, version tags matching `v*`, and manual [workflow runs](.github/workflows/docker-publish.yml) build the image and push the same tags to:

- **Docker Hub:** [`vergissberlin/apigee-hybrid-development`](https://hub.docker.com/r/vergissberlin/apigee-hybrid-development)
- **GitHub Container Registry:** `ghcr.io/<lowercase-owner>/<lowercase-repo>` (mirrors the GitHub repository name)

**Repository setup:** add Actions secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`. GHCR uses `GITHUB_TOKEN` with `packages: write`. After the first GHCR push, adjust package visibility under the repository or organization **Packages** settings if you want anonymous `docker pull`.

## Build the Image Locally

```bash
docker build -t apigee-hybrid-development:local .
```

On **Apple Silicon** (arm64), the image matches your machine. To match **CI** (`linux/amd64` only), use:

```bash
docker build --platform linux/amd64 -t apigee-hybrid-development:local .
```

The default shell is **bash** (`CMD ["/bin/bash"]`). **zsh** is also installed. **`APIGEE_HELM_CHARTS_HOME`**, **`CHART_REPO`**, and **`CHART_VERSION`** are set in the environment and in `/root/.zshrc` (see [Download charts](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts)). The image build pulls the default Apigee Hybrid charts (operator, datastore, env, ingress-manager, org, redis, telemetry, virtualhost) from **`CHART_REPO`** at **`CHART_VERSION`** (override at build with `--build-arg CHART_VERSION=…`). Pulling from Google’s OCI registry may require **`gcloud auth application-default login`** (or equivalent) on the host building the image. Example:

```bash
docker run -it --rm vergissberlin/apigee-hybrid-development:latest zsh
```

## Installation Guide

For a full step-by-step guide to install Apigee Hybrid v1.16 on Azure AKS, see:

📖 **[docs/install-apigee-hybrid.md](docs/install-apigee-hybrid.md)**

The container image includes an **interactive setup script** at `/workspace/scripts/apigee-hybrid-aks-setup.sh` (also [scripts/apigee-hybrid-aks-setup.sh](scripts/apigee-hybrid-aks-setup.sh) in this repository). It sources shared CLI helpers from [scripts/misc-cli-utils.sh](scripts/misc-cli-utils.sh) (colored banners, `info`/`warn`/`error`, `prompt`/`confirm`, `run_cmd`, etc.). It walks through Google’s official hybrid install steps **3–11** (namespace, service accounts, authentication, TLS, `overrides.yaml`, control-plane API access, cert-manager, CRDs, Helm installs), prompts for variables, skips chart download when charts are already baked into the image, and highlights AKS-specific commands (for example `az aks get-credentials` and OIDC for Workload Identity Federation). Run `bash /workspace/scripts/apigee-hybrid-aks-setup.sh --help` inside the container for usage and step names.

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

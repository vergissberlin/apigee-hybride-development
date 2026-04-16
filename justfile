# Apigee Hybrid development image — https://github.com/vergissberlin/apigee-hybride-development
# Requires: Docker, https://github.com/casey/just
#
# Setup script tests: test-setup-smoke, test-setup-prereq-mock, test-setup-prereq-stubs (see CONTRIBUTING.md).
#
# Override image: just --set image ghcr.io/owner/apigee-hybride-development:latest run

# Published image (override with `just --set image …`)
image := "vergissberlin/apigee-hybride-development:latest"

# Registry images are linux/amd64 (see CI). Required on Apple Silicon (arm64).
platform := "linux/amd64"

# Local tag after `just build`
image-local := "apigee-hybride-development:local"

# Default: interactive bash with kube + gcloud config from the host
default: run

# Pull the configured image from the registry
pull:
    docker pull --platform "{{platform}}" "{{image}}"

# Build the image from this directory (linux/amd64 matches CI)
build:
    docker build --platform linux/amd64 -t "{{image-local}}" .

# Run the published image (interactive)
run: pull
    docker run -it --rm --platform "{{platform}}" \
      -v "$HOME/.kube:/root/.kube" \
      -v "$HOME/.config/gcloud:/root/.config/gcloud" \
      -w /workspace \
      "{{image}}" \
      /bin/zsh

# Run a locally built image (runs `build` first)
run-local: build
    docker run -it --rm --platform "{{platform}}" \
      -v "$HOME/.kube:/root/.kube" \
      -v "$HOME/.config/gcloud:/root/.config/gcloud" \
      -w /workspace \
      "{{image-local}}" \
      /bin/zsh

# Tier 1 — bash -n + --help (matches CI setup-script-test workflow)
test-setup-smoke: build
    docker run --rm --platform "{{platform}}" "{{image-local}}" \
      /bin/bash -n /workspace/scripts/apigee-hybrid-aks-setup.sh
    docker run --rm --platform "{{platform}}" "{{image-local}}" \
      /bin/bash -n /workspace/scripts/misc-cli-utils.sh
    docker run --rm --platform "{{platform}}" "{{image-local}}" \
      apigee-hybrid-aks-setup --help

# Tier 2 — prereq without real AKS (SKIP_* env vars; see docs/setup-script-environment.md)
test-setup-prereq-mock: build
    docker run --rm --platform "{{platform}}" \
      -e APIGEE_SETUP_NONINTERACTIVE=1 \
      -e SKIP_AZ_GET_CREDENTIALS=1 \
      -e SKIP_KUBECTL_CLUSTER_CHECK=1 \
      -e PROJECT_ID=local-test-project \
      -e ORG_NAME=local-test-project \
      "{{image-local}}" \
      apigee-hybrid-aks-setup prereq

# Tier 2 (alternate) — stub az/kubectl on PATH (see tests/integration/stubs/README.md)
test-setup-prereq-stubs: build
    docker run --rm --platform "{{platform}}" \
      -v "{{justfile_directory()}}/tests/integration/stubs:/integration-stubs" \
      -e PATH="/integration-stubs:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      -e APIGEE_SETUP_NONINTERACTIVE=1 \
      -e PROJECT_ID=local-test-project \
      -e ORG_NAME=local-test-project \
      "{{image-local}}" \
      apigee-hybrid-aks-setup prereq

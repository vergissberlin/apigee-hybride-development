# Apigee Hybrid development image — https://github.com/vergissberlin/apigee-hybride-development
# Requires: Docker, https://github.com/casey/just
#
# Override image: just --set image ghcr.io/owner/apigee-hybride-development:latest run

# Published image (override with `just --set image …`)
image := "vergissberlin/apigee-hybride-development:latest"

# Local tag after `just build`
image-local := "apigee-hybride-development:local"

# Default: interactive bash with kube + gcloud config from the host
default: run

# Pull the configured image from the registry
pull:
    docker pull "{{image}}"

# Build the image from this directory (linux/amd64 matches CI)
build:
    docker build --platform linux/amd64 -t "{{image-local}}" .

# Run the published image (interactive)
run:
    docker run -it --rm \
      -v "$HOME/.kube:/root/.kube" \
      -v "$HOME/.config/gcloud:/root/.config/gcloud" \
      -w /workspace \
      "{{image}}" \
      /bin/bash

# Run a locally built image (runs `build` first)
run-local: build
    docker run -it --rm \
      -v "$HOME/.kube:/root/.kube" \
      -v "$HOME/.config/gcloud:/root/.config/gcloud" \
      -w /workspace \
      "{{image-local}}" \
      /bin/bash

# Same mounts, start zsh (oh-my-zsh in base image)
zsh:
    docker run -it --rm \
      -v "$HOME/.kube:/root/.kube" \
      -v "$HOME/.config/gcloud:/root/.config/gcloud" \
      -w /workspace \
      "{{image}}" \
      zsh

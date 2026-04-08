FROM vergissberlin/ubuntu-development:24.04

# Helm 3.x binary from get.helm.sh (pinned). Avoids apt/baltocdn HTTP/2 PROTOCOL_ERROR in some CI/Docker builds.
ARG HELM_VERSION=v3.20.1

LABEL maintainer="vergissberlin" \
      description="Docker image for Apigee Hybrid development on Azure AKS" \
      version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    pipx \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    jq \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud CLI (gcloud)
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI (az)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
        | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/*

# Install Helm (official tarball; more reliable than baltocdn apt repo under flaky HTTP/2)
RUN curl -fsSL --http1.1 "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
    && tar -C /tmp -xzf /tmp/helm.tgz \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64 /tmp/helm.tgz \
    && helm version

# Install HTTPie via pipx (isolated environment, avoids system package conflicts)
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install httpie

# Apigee Hybrid charts are published as OCI in Google Artifact Registry (the legacy
# storage.googleapis.com Helm index is no longer valid). Pull charts when installing,
# per https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts
# Example: helm pull oci://us-docker.pkg.dev/apigee-release/apigee-hybrid-helm-charts/apigee-operator --version <chart-version> --untar

# Set working directory
WORKDIR /workspace

CMD ["/bin/bash"]

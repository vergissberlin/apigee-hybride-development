FROM vergissberlin/ubuntu-development:24.04

# Set by Docker BuildKit to match the build platform (amd64 on CI, arm64 on Apple Silicon, …).
ARG TARGETARCH

# Helm 3.x binary from get.helm.sh (pinned). Avoids apt/baltocdn HTTP/2 PROTOCOL_ERROR in some CI/Docker builds.
ARG HELM_VERSION=v3.20.1

# Apigee Hybrid Helm charts (OCI). Override: docker build --build-arg CHART_VERSION=...
ARG CHART_VERSION=1.16.0-hotfix.1

LABEL maintainer="vergissberlin" \
      description="Docker image for Apigee Hybrid development on Azure AKS" \
      version="1.3.1"

ENV DEBIAN_FRONTEND=noninteractive

# Apigee Hybrid: chart download directory (see install-download-charts v1.16)
ENV APIGEE_HELM_CHARTS_HOME=/workspace/apigee-hybrid/helm-charts \
    CHART_REPO=oci://us-docker.pkg.dev/apigee-release/apigee-hybrid-helm-charts \
    CHART_VERSION=${CHART_VERSION}

# Install prerequisites
RUN apt update && apt install -y --no-install-recommends \
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
    openssl \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud CLI (gcloud)
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt update \
    && apt install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI (az)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/azure-cli.list \
    && apt update \
    && apt install -y --no-install-recommends azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
        | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list \
    && apt update \
    && apt install -y --no-install-recommends kubectl \
    && rm -rf /var/lib/apt/lists/*

# Install Helm (official tarball; more reliable than baltocdn apt repo under flaky HTTP/2)
RUN curl -fsSL --http1.1 "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" -o /tmp/helm.tgz \
    && tar -C /tmp -xzf /tmp/helm.tgz \
    && mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf "/tmp/linux-${TARGETARCH}" /tmp/helm.tgz \
    && helm version

# Install HTTPie via pipx (isolated environment, avoids system package conflicts)
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install httpie

# Apigee Hybrid charts: OCI in Artifact Registry
# https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts

WORKDIR /workspace

COPY scripts/misc-cli-utils.sh scripts/apigee-hybrid-aks-setup.sh /workspace/scripts/
RUN chmod +x /workspace/scripts/apigee-hybrid-aks-setup.sh \
    && ln -sf /workspace/scripts/apigee-hybrid-aks-setup.sh /usr/bin/apigee-hybrid-aks-setup

RUN mkdir -p apigee-hybrid/helm-charts

WORKDIR /workspace/apigee-hybrid/helm-charts

# Append to /root/.zshrc — do not overwrite; base image (ubuntu-development) ships oh-my-zsh here.
RUN { \
    echo ""; \
    echo "# Apigee Hybrid (this image)"; \
    echo "export APIGEE_HELM_CHARTS_HOME=${APIGEE_HELM_CHARTS_HOME}"; \
    echo "export CHART_REPO=${CHART_REPO}"; \
    echo "export CHART_VERSION=${CHART_VERSION}"; \
} >> /root/.zshrc

RUN set -eux; \
    helm pull "${CHART_REPO}/apigee-operator" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-datastore" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-env" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-ingress-manager" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-org" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-redis" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-telemetry" --version "${CHART_VERSION}" --untar; \
    helm pull "${CHART_REPO}/apigee-virtualhost" --version "${CHART_VERSION}" --untar


CMD ["/bin/bash"]

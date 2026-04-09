# Running the image in a Kubernetes cluster

This document describes how to run **`vergissberlin/apigee-hybride-development`** as a **Pod**, **Job**, or **CronJob** inside a cluster. It complements the default [Quick Start](../README.md#quick-start), which assumes **`docker run`** on your workstation with host bind mounts (`~/.kube`, `~/.config/gcloud`).

For automating **`apigee-hybrid-aks-setup`**, configure environment variables as in [setup-script-environment.md](setup-script-environment.md) and set **`APIGEE_SETUP_NONINTERACTIVE=1`** when you need non-interactive execution.

## When this is useful

- **Job:** one-shot automation (e.g. a scripted phase of the hybrid install) with env-driven configuration.
- **Pod:** long-lived utility shell for cluster operators (use sparingly; secure credentials and RBAC).
- **CronJob:** scheduled tasks that call CLIs inside the image.

This is **not** a replacement for the official Apigee Hybrid runtime components; it is the **development/tooling** image documented in this repository.

## Platform

Published images are built for **`linux/amd64`** (same as CI). Ensure your nodes can run amd64 workloads, or use a node pool / selector that matches this architecture.

## Pulling the image

The image on Docker Hub is public. If you pull from **GHCR** or another private registry, create an **`imagePullSecret`** and reference it in the Pod spec (`spec.imagePullSecrets`).

## `kubectl` and `helm` (same cluster)

Do **not** mount a laptop’s **`~/.kube`** into the Pod. Inside the cluster, prefer **in-cluster credentials**:

- Kubernetes mounts a service account token under **`/var/run/secrets/kubernetes.io/serviceaccount`**.
- **`kubectl`** and **`helm`** use the in-cluster config when **`KUBERNETES_SERVICE_HOST`** is set (default for Pods).

Assign a dedicated **ServiceAccount** to the Pod and grant **RBAC** (Role or ClusterRole + RoleBinding) with only the API permissions your task needs. Avoid using `cluster-admin` for routine Jobs.

If the Pod must talk to a **different** cluster, distribute a **kubeconfig** as a Secret and mount it (e.g. under `/root/.kube/config`), and set **`KUBECONFIG`**. This is a special case; default to in-cluster access when the Job runs **on** the target cluster.

## Google Cloud (`gcloud`, Helm OCI to Artifact Registry)

Interactive **`gcloud auth login`** is not suitable for Pods. Use one of:

1. **Application Default Credentials (ADC)** — mount a JSON file from a Kubernetes Secret, for example:
   - Path: **`/root/.config/gcloud/application_default_credentials.json`**
   - Create the Secret from a key file (you generate the key and credentials outside this repo):

   ```bash
   kubectl create secret generic gcloud-adc \
     --from-file=application_default_credentials.json=./your-adc-or-key.json \
     -n your-namespace
   ```

2. **Whole config tree** — if you need more than ADC, mount an entire Secret (or use a CSI driver / external secrets operator) under **`/root/.config/gcloud`** as a volume. Keep the Secret minimal (least privilege IAM on the Google service account).

See Google’s documentation for [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials).

## Azure CLI (`az`)

For non-interactive use, prefer an **Azure AD application (service principal)** and pass credentials via environment variables (often sourced from a Secret):

| Variable | Purpose |
|----------|---------|
| `AZURE_CLIENT_ID` | Application (client) ID |
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_CLIENT_SECRET` | Client secret |

Example (values are placeholders; store real data only in Secrets):

```yaml
env:
  - name: AZURE_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: azure-sp
        key: client-id
  - name: AZURE_TENANT_ID
    valueFrom:
      secretKeyRef:
        name: azure-sp
        key: tenant-id
  - name: AZURE_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: azure-sp
        key: client-secret
```

You can create the Secret with:

```bash
kubectl create secret generic azure-sp \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=tenant-id=YOUR_TENANT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  -n your-namespace
```

Mounting **`~/.azure`** from a laptop is possible but is usually weaker for automation than service-principal env vars.

## Security

- Store credentials only in **Kubernetes Secrets** (or **External Secrets**, **Vault**, etc.); never commit them to git.
- Restrict RBAC for the Pod’s ServiceAccount and IAM roles for GCP/Azure identities.
- Prefer short-lived tokens and rotation where your platform supports them.

## Minimal example: Job with GCP ADC and Azure SP env

The following illustrates structure only. Replace namespaces, image tags, and Secret names to match your environment. **`YOUR_REGISTRY/IMAGE:tag`** can be `vergissberlin/apigee-hybride-development:latest` from Docker Hub.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: apigee-hybrid-tooling-example
  namespace: default
spec:
  template:
    spec:
      serviceAccountName: apigee-tooling-sa   # create + bind RBAC separately
      restartPolicy: Never
      containers:
        - name: tooling
          image: vergissberlin/apigee-hybride-development:latest
          imagePullPolicy: IfNotPresent
          # Optional: non-interactive setup script
          # command: ["/bin/bash", "-lc", "apigee-hybrid-aks-setup prereq"]
          env:
            - name: APIGEE_SETUP_NONINTERACTIVE
              value: "1"
            - name: AZURE_CLIENT_ID
              valueFrom:
                secretKeyRef:
                  name: azure-sp
                  key: client-id
            - name: AZURE_TENANT_ID
              valueFrom:
                secretKeyRef:
                  name: azure-sp
                  key: tenant-id
            - name: AZURE_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: azure-sp
                  key: client-secret
          volumeMounts:
            - name: gcloud-adc
              mountPath: /root/.config/gcloud/application_default_credentials.json
              subPath: application_default_credentials.json
              readOnly: true
      volumes:
        - name: gcloud-adc
          secret:
            secretName: gcloud-adc
```

Create **`gcloud-adc`** and **`azure-sp`** Secrets in the same namespace before applying the Job. Create **`apigee-tooling-sa`** and RoleBindings so the Job can run **`kubectl`** / **`helm`** only as needed.

## AKS note

On **Azure Kubernetes Service**, this image is often used from a dev machine with **`docker run`**. Running it **inside** the cluster follows the same credential patterns above; use Azure SP env vars for **`az`** and ADC (or workload identity patterns your org supports) for **`gcloud`** when pulling Apigee Helm charts from Google’s OCI registry.

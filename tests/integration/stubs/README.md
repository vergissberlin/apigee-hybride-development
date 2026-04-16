# Integration test stubs (`az` / `kubectl`)

These scripts sit **first on `PATH`** so `apigee-hybrid-aks-setup.sh prereq` can run in non-interactive mode without touching a real AKS cluster:

- **`az`** — exits successfully for `az aks get-credentials …`; all other subcommands run via `/usr/bin/az`.
- **`kubectl`** — prints minimal output for `kubectl cluster-info` and `kubectl get nodes`; all other subcommands run via `/usr/bin/kubectl`.

## Usage

From the repository root (with `just`):

```bash
just test-setup-prereq-stubs
```

Or manually (after building `apigee-hybride-development:local`):

```bash
docker run --rm --platform linux/amd64 \
  -v "$(pwd)/tests/integration/stubs:/integration-stubs" \
  -e PATH="/integration-stubs:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -e APIGEE_SETUP_NONINTERACTIVE=1 \
  -e PROJECT_ID=local-test-project \
  -e ORG_NAME=local-test-project \
  apigee-hybride-development:local \
  apigee-hybrid-aks-setup prereq
```

Prefer **`SKIP_AZ_GET_CREDENTIALS=1`** and **`SKIP_KUBECTL_CLUSTER_CHECK=1`** when you do not need to exercise those code paths (see [docs/setup-script-environment.md](../../docs/setup-script-environment.md)); CI uses that approach.

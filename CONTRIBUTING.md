# Contributing

Thanks for improving this project. This repository ships a **Docker image** for Apigee Hybrid development on Azure AKS. Contributions that keep the image maintainable, secure, and well documented are welcome.

## Ground rules

- Use **inclusive, respectful** communication in issues and pull requests.
- Do **not** commit secrets, tokens, kubeconfigs, or cloud credentials. Use local files or your own private environment; never open a PR that contains real credentials.
- Match existing style in the **Dockerfile** and docs: clear comments only where they add context, minimal churn in unrelated files.

## How to contribute

1. **Open an issue** first when you plan a larger change (new tools in the image, breaking base-image bumps, workflow changes). That avoids duplicate work and helps align on scope.
2. **Fork the repository**, create a branch from `main`, and open a **pull request** when your change is ready.
3. Describe **what** changed and **why** in the PR description. Link related issues when applicable.

## Build the image locally

```bash
docker build -t apigee-hybride-development:local .
```

To match the **published** image and **CI** (always `linux/amd64`), build with:

```bash
docker build --platform linux/amd64 -t apigee-hybride-development:local .
```

On **Apple Silicon**, a plain `docker build` produces an **arm64** image (different from the registry). Use `--platform linux/amd64` when you want the same architecture as Docker Hub / GHCR.

The default shell is **bash** (`CMD ["/bin/bash"]`). **zsh** is also installed. **`APIGEE_HELM_CHARTS_HOME`**, **`CHART_REPO`**, and **`CHART_VERSION`** are set in the environment and in `/root/.zshrc` (see [Download charts](https://cloud.google.com/apigee/docs/hybrid/v1.16/install-download-charts)). The image build pulls the default Apigee Hybrid charts (operator, datastore, env, ingress-manager, org, redis, telemetry, virtualhost) from **`CHART_REPO`** at **`CHART_VERSION`** (override at build with `--build-arg CHART_VERSION=…`). Pulling from Google’s OCI registry may require **`gcloud auth application-default login`** (or equivalent) on the host building the image. Example:

```bash
docker run -it --rm --platform linux/amd64 vergissberlin/apigee-hybride-development:latest zsh
```

## Local checks

Before opening a PR, build and run the container using the same platform as CI when possible (see [Build the image locally](#build-the-image-locally)):

```bash
docker build --platform linux/amd64 -t apigee-hybride-development:local .
docker run --rm -it --platform linux/amd64 apigee-hybride-development:local zsh
```

If you changed tooling versions or install steps, run the container briefly and sanity-check the relevant CLI (`gcloud`, `az`, `kubectl`, `helm`, etc.).

## Setup script tests (local and CI)

The interactive installer is [`scripts/apigee-hybrid-aks-setup.sh`](scripts/apigee-hybrid-aks-setup.sh). Automated checks run in GitHub Actions (workflow [`.github/workflows/setup-script-test.yml`](.github/workflows/setup-script-test.yml)) on pull requests that touch the scripts, Dockerfile, `justfile`, or [`tests/integration/`](tests/integration/). You can also run the workflow manually (**Actions → Setup script tests → Run workflow**).

**What is covered**

- **Tier 1 (smoke):** `/bin/bash -n` on the setup script and [`scripts/misc-cli-utils.sh`](scripts/misc-cli-utils.sh), then `apigee-hybrid-aks-setup --help` inside a freshly built **`linux/amd64`** image (same architecture family as Azure Cloud Shell on **x86_64**). This verifies syntax and that required CLIs are on `PATH` in the image.
- **Tier 2 (integration, no cloud):** `apigee-hybrid-aks-setup prereq` with `APIGEE_SETUP_NONINTERACTIVE=1` and **`SKIP_AZ_GET_CREDENTIALS=1`** / **`SKIP_KUBECTL_CLUSTER_CHECK=1`** so CI does not need Azure or a kubeconfig. Variables are documented in [`docs/setup-script-environment.md`](docs/setup-script-environment.md).
- **Alternate Tier 2:** mount [`tests/integration/stubs/`](tests/integration/stubs/) first on `PATH` so `az` / `kubectl` are stubbed; see that folder’s README. The [`justfile`](justfile) recipe `test-setup-prereq-stubs` runs that mode locally.

**Local commands** (requires [just](https://github.com/casey/just); needs Docker with `linux/amd64` support, e.g. `--platform linux/amd64` on Apple Silicon):

```bash
just test-setup-smoke
just test-setup-prereq-mock
# optional: stub PATH instead of SKIP_* env vars
just test-setup-prereq-stubs
```

**Azure Cloud Shell**

Docker-based tests approximate the tooling stack and **amd64** userspace; they do **not** replicate Cloud Shell identity, mounts, or kernel. After meaningful changes to auth or cluster steps, do a short manual run in Azure Cloud Shell before release.

### Dev Containers

The repository includes [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json), which builds from the same [`Dockerfile`](Dockerfile). The editor mounts this repo under `/workspaces/…` so your working tree stays editable; chart tarballs baked into **`/workspace/apigee-hybrid/helm-charts`** in the image remain available at the default **`APIGEE_HELM_CHARTS_HOME`**. Run the setup script from the cloned repo so you use your current sources, for example:

```bash
bash scripts/apigee-hybrid-aks-setup.sh --help
```

## Commit messages

Use **[Conventional Commits](https://www.conventionalcommits.org/)** in English (for example `fix: pin kubectl apt repo`, `feat: add tool xyz`, `docs: clarify volume mounts`). This keeps the history readable and matches **[Release Please](.github/workflows/release-please.yml)**, which updates [CHANGELOG.md](CHANGELOG.md) from those commits.

Common types used here: `feat`, `fix`, `docs`, `perf`, `refactor`, `ci`, `chore`, `build`, `test`.

## Releases and CI

### Docker image publishing

The [docker-publish workflow](.github/workflows/docker-publish.yml) builds and pushes the image on pushes to `main`, on git tags matching `v*`, via manual workflow dispatch, and on a **weekly schedule** (Mondays 06:00 UTC) so the image is rebuilt regularly without a code change. Registry tags are **`latest`** on the default branch (plus **semver** tags when you push `v*`), not a branch-name tag such as `main`. The same image reference is published to:

- **Docker Hub:** [`vergissberlin/apigee-hybride-development`](https://hub.docker.com/r/vergissberlin/apigee-hybride-development)
- **GitHub Container Registry:** `ghcr.io/<lowercase-owner>/<lowercase-repo>` (mirrors the GitHub repository name)

**Repository setup for maintainers:** add Actions secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`. GHCR uses `GITHUB_TOKEN` with `packages: write`. After the first GHCR push, adjust package visibility under the repository or organization **Packages** settings if you want anonymous `docker pull`.

If you cut release tags, keep them consistent with how registry tagging should work for consumers (see the workflow’s tag filters).

### GitHub Wiki sync

The [wiki-sync workflow](.github/workflows/wiki-sync.yml) updates the repository’s **[GitHub Wiki](https://github.com/vergissberlin/apigee-hybride-development/wiki)** from this repo’s documentation. It runs on pushes to `main` when `README.md`, `docs/**`, `CONTRIBUTING.md`, `CHANGELOG.md`, or the workflow file changes, and can be triggered manually (**Actions → Sync wiki → Run workflow**).

**What gets published:** `README.md` becomes the wiki **Home** page (with a short header from [`docs/wiki/_Header.md`](docs/wiki/_Header.md)), files under [`docs/`](docs/) are copied into the wiki git with the same folder layout, and [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`CHANGELOG.md`](CHANGELOG.md) become **Contributing** and **Changelog**. Layout files [`docs/wiki/_Sidebar.md`](docs/wiki/_Sidebar.md) and [`docs/wiki/_Footer.md`](docs/wiki/_Footer.md) define the wiki sidebar and footer. **In the wiki UI, internal links must use each page’s unique name only** (for example `install-apigee-hybrid`, not `docs/install-apigee-hybrid`); the sync job rewrites links accordingly so navigation matches [GitHub Wiki’s linking rules](https://github.com/tajmone/github-tests/wiki/subfolders).

**Single source of truth:** edit documentation in this repository. Changes made only in the wiki UI may be overwritten on the next successful sync.

**Authentication:** the job uses `GITHUB_TOKEN` by default. If the push to `*.wiki.git` fails (for example due to organization policy), add a repository secret **`WIKI_SYNC_TOKEN`**: a classic PAT with `repo` scope, or a fine-grained token with **Contents** read/write on this repository.

### Release Please

- **Release Please** runs on pushes to `main` and opens/maintains release PRs using [`.release-please-config.json`](.release-please-config.json).

#### "Not permitted to create or approve pull requests"

Release Please fails at the step where it opens or updates a pull request. The workflow already requests the right token scopes (`contents: write`, `pull-requests: write` in [`.github/workflows/release-please.yml`](.github/workflows/release-please.yml)), but **GitHub can still block PR creation** until you either enable the repository setting below or use a separate token.

#### Fix (recommended): allow GitHub Actions to create PRs

In the repository on GitHub:

1. Go to **Settings → Actions → General → Workflow permissions**.
2. Set **Workflow permissions** to **Read and write permissions**.
3. Enable **Allow GitHub Actions to create and approve pull requests**.

Re-run the workflow after saving. This matches the restriction enforced by GitHub’s pull request API. If the checkbox is missing or grayed out, an **organization or enterprise** admin must allow it at a higher level. See [GitHub Docs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#preventing-github-actions-from-creating-or-approving-pull-requests).

#### Fix (alternative): PAT when org policy blocks the checkbox

If the setting cannot be enabled:

1. Create a **classic** Personal Access Token with at least:
   - **`repo`** (full control of private repositories), or
   - **`public_repo`** if the repository is **public** and that scope is sufficient for your setup.
2. Add it as a repository secret named **`RELEASE_PLEASE_TOKEN`**.
3. The workflow uses that token when the secret is set:

```yaml
token: ${{ secrets.RELEASE_PLEASE_TOKEN || github.token }}
```

Re-run the job; Release Please will authenticate with the PAT and can create or update the release PR even when `GITHUB_TOKEN` is restricted.

#### Log noise: "commit could not be parsed"

Logs may show lines such as `commit could not be parsed` or parser errors like `unexpected token` while scanning history. Those mean **some commits are not valid Conventional Commits**; Release Please skips them for changelog purposes. They are **separate** from the PR-permission failure: the job can get far enough to create commits and still fail only when opening the PR. Prefer Conventional Commit messages on new work; cleaning up old history is optional and not required to fix the permission error.

## Documentation

- User-facing documentation in this repo is written in **English** (for example [README.md](README.md) and [docs/](docs/)).
- When you change how the image is built or run, update the README or the relevant doc under `docs/` in the same PR when practical.

## Editor configuration

The repo includes [`.editorconfig`](.editorconfig). Using an EditorConfig-aware editor helps keep formatting consistent.

## License

By contributing, you agree that your contributions will be licensed under the same terms as the project — see [LICENSE](LICENSE).

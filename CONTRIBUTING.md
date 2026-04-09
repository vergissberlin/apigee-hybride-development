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

## Local checks

Before opening a PR:

```bash
docker build -t apigee-hybride-development:local .
docker run --rm -it apigee-hybride-development:local zsh
```

If you changed tooling versions or install steps, run the container briefly and sanity-check the relevant CLI (`gcloud`, `az`, `kubectl`, `helm`, etc.).

## Commit messages

Use **[Conventional Commits](https://www.conventionalcommits.org/)** in English (for example `fix: pin kubectl apt repo`, `feat: add tool xyz`, `docs: clarify volume mounts`). This keeps the history readable and matches **[Release Please](.github/workflows/release-please.yml)**, which updates [CHANGELOG.md](CHANGELOG.md) from those commits.

Common types used here: `feat`, `fix`, `docs`, `perf`, `refactor`, `ci`, `chore`, `build`, `test`.

## Releases and CI

### Docker image publishing

The [docker-publish workflow](.github/workflows/docker-publish.yml) builds and pushes the image on pushes to `main`, on git tags matching `v*`, via manual workflow dispatch, and on a **weekly schedule** (Mondays 06:00 UTC) so the image is rebuilt regularly without a code change. The same logical tag is published to:

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

# GitHub App Bot Setup for PR Radar CI

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `pr-radar-verify-work` | Verify changes by running CLI against the test repo |

## Background

PRRadar runs as a GitHub Actions workflow that analyzes PRs and posts review comments. By default, using `GITHUB_TOKEN` makes comments appear as "github-actions[bot]". We use a **GitHub App** to give PRRadar its own bot identity ("PR Radar[bot]").

This was validated end-to-end on `gestrich/PRRadar-TestRepo` (PR #16 — comment posted as `pr-radar-app[bot]`).

### How the token flow works

1. Store **App ID** as a repo-level Actions **variable** (`PR_RADAR_APP_ID`) and **private key (PEM)** as a repo-level Actions **secret** (`PR_RADAR_PRIVATE_KEY`)
2. Workflow uses `actions/create-github-app-token@v2` to mint a 1-hour installation token
3. Steps that call `gh` CLI or PRRadar CLI set `GITHUB_TOKEN` env from the token output

### Lessons learned from TestRepo setup

- The GitHub App must be **installed** on the target repo (creating the app alone is not enough)
- Use **repository variables/secrets**, NOT environment variables/secrets (environment-scoped ones require `environment:` in the workflow)
- PRRadar's credential resolver looks for `GITHUB_TOKEN`, not `GH_TOKEN` — use `GITHUB_TOKEN` as the env var name
- The `permissions` block can be removed since the GitHub App's own permissions govern access
- The OAuth/callback/device flow sections during App creation can all be left blank — they're not needed for CI token flow
- GitHub App names are globally unique — pick a variation if the name is taken
- Set `GITHUB_TOKEN` per-step (not job-level) because job-level env can't reference step outputs
- `workflow_dispatch` runs the workflow file from the **default branch** — use `--ref <branch>` via `gh workflow run` to run a workflow from a different branch

### GitHub App permissions needed

- **Contents: read** — for checking out code
- **Pull requests: read/write** — for reading PR diffs and posting review comments
- **Issues: read/write** — for posting issue comments

## Phases

## - [x] Phase 1: Create GitHub App and configure secrets (TestRepo - DONE)

Completed for `gestrich/PRRadar-TestRepo`. App name: `pr-radar-app`.

## - [x] Phase 2: Update TestRepo workflow (DONE)

Updated `.github/workflows/pr-review.yml` to use GitHub App token.

## - [x] Phase 3: Validate on TestRepo (DONE)

PR #16 — comment posted as `pr-radar-app[bot]`.

## Setting up PR Radar on a new repo

### 1. Install the GitHub App

1. Go to github.com/apps/pr-radar-app and click **Install**
2. Select the org or account that owns the target repo
3. Choose "Only select repositories" and pick the repo

### 2. Configure secrets and variables

In the repo's settings (Settings > Secrets and variables > Actions):

- **Variables** tab > "New repository variable": `PR_RADAR_APP_ID` = (the App ID from the GitHub App settings)
- **Secrets** tab > "New repository secret": `PR_RADAR_PRIVATE_KEY` = (paste the PEM file contents)
- **Secrets** tab: Ensure `ANTHROPIC_API_KEY` is set

### 3. Add the workflow

Add a `.github/workflows/pr-radar.yml` that:

1. Uses `actions/create-github-app-token@v2` to mint an installation token
2. Passes the token to `actions/checkout@v4` via `token:`
3. Sets `GITHUB_TOKEN` per-step (not job-level) on steps that need GitHub API access (sync, prepare, comment)
4. Does **not** include a `permissions` block (the app's own permissions govern access)

See `gestrich/PRRadar-TestRepo/.github/workflows/pr-review.yml` for a reference implementation.

### 4. Validate

- Trigger via `gh workflow run "PR Radar" --ref <branch> -f pr_number=<N> -f mode=regex`
- Verify comments appear as `pr-radar-app[bot]`

# GitHub repository setup

Use this sequence after the repository owner, name, visibility, license, release
approver, and support route are approved. Do not replace those decisions with
examples from this document.

## Safe creation order

1. Keep `RELEASE_STATUS` at `HOLD`.
2. Add the approved license and replace the repository placeholders in the
   README.
3. Configure the intended local Git author identity, stage the reviewed files,
   but do not create the initial commit yet.
4. Preview and validate the combined initial-commit/repository/push operation:

   ```bash
   bash scripts/bootstrap-github-repository.sh --plan \
     --repository OWNER/REPOSITORY \
     --public \
     --description "APPROVED ONE-SENTENCE DESCRIPTION"

   bash scripts/bootstrap-github-repository.sh --check \
     --repository OWNER/REPOSITORY \
     --public \
     --description "APPROVED ONE-SENTENCE DESCRIPTION"
   ```

   GitHub Free, Pro, and Team provide required reviewers for public
   repositories; a private repository needs the corresponding Enterprise
   capability. For that approved case, replace `--public` with `--private` and
   add `--private-enterprise`. Do not choose private first and discover after
   partial setup that the release approval gate is unavailable.

5. After reviewing the preflight, explicitly create the root commit, repository,
   origin and initial push:

   ```bash
   bash scripts/bootstrap-github-repository.sh --apply \
     --repository OWNER/REPOSITORY \
     --public \
     --description "APPROVED ONE-SENTENCE DESCRIPTION"
   ```

   The bootstrap refuses an existing commit, origin or remote repository and
   never creates a tag or Release. Let CI run once and record the resulting
   check names.

6. Configure the controls below before creating any `v*` tag.
   Preview the repository-specific values first:

   ```bash
   bash scripts/github-repository-controls.sh --plan \
     --repository OWNER/REPOSITORY \
     --release-actor user:RELEASE_ACTOR \
     --release-reviewer user:RELEASE_REVIEWER
   ```

   After reviewing the plan, apply the initial controls:

   ```bash
   bash scripts/github-repository-controls.sh --apply \
     --repository OWNER/REPOSITORY \
     --release-actor user:RELEASE_ACTOR \
     --release-reviewer user:RELEASE_REVIEWER
   ```

   Use `team:TEAM_SLUG` instead of `user:LOGIN` for an organization team. The
   script requires distinct release-actor and reviewer identities, refuses to
   initialize a repository that already has a `v*` tag or Release, and reads
   every API-visible setting back after applying it. Add
   `--private-enterprise` to every plan/apply/check invocation only for an
   approved private Enterprise repository.
7. Verify the controls again at any time with the script's read-only mode:

   ```bash
   bash scripts/github-repository-controls.sh --check \
     --repository OWNER/REPOSITORY \
     --release-actor user:RELEASE_ACTOR \
     --release-reviewer user:RELEASE_REVIEWER
   ```

   The individual read-only API commands below remain useful for attaching raw
   responses to release evidence.
8. Complete product intake, workflow evidence, clean-Mac qualification, and the
   release checklist in a reviewed pull request.
9. Only the named release owner changes `RELEASE_STATUS` to `GO`.
10. Create and push the matching `v<VERSION>` tag from the protected default
    branch. The Release workflow still pauses at `github-release` approval.

The initial push cannot publish because the repository contains `HOLD`, and the
Release workflow only responds to tags. Even after `GO`, the workflow refuses
publication while product intake, the beta runbook, the checklist, License, the
README, or product release notes contain unresolved release markers.

## Default-branch ruleset

Create an **active branch ruleset** targeting `~DEFAULT_BRANCH`:

- require a pull request before merging;
- require at least one approval;
- dismiss stale approvals when new commits are pushed;
- require all review conversations to be resolved;
- block force pushes and deletion;
- require the repository's observed CI checks, expected to include:
  - `repository checks`;
  - `macOS prerequisites (arm64)`;
  - `macOS prerequisites (x86_64)`;
  - `macOS isolated install (arm64)`;
- configure no branch-ruleset bypass actor for the beta. Any emergency change
  must be a separately reviewed and auditable control change, not an always-on
  administrator exception.

Confirm the exact names from the first CI run rather than relying only on the
expected labels above.

## Release-tag ruleset

Create an **active tag ruleset** targeting `refs/tags/v*`:

- restrict creation to the named release actor or team;
- restrict updates and deletion;
- disallow a broad always-on bypass;
- keep the creation actor separate from the required Release environment
  reviewer where team size and GitHub plan allow.

The workflow also verifies that the tag commit is reachable from the protected
default branch. Once its GitHub Release is published, release immutability adds
an independent tag and asset lock.

## Release environment

Create an environment named exactly `github-release`:

- add exactly the one approved required reviewer recorded by the setup script;
- enable prevention of self-review where the repository plan supports it;
- disable **Allow administrators to bypass configured protection rules** in
  the GitHub UI and attach a screenshot or settings audit record; GitHub's
  current REST environment schema does not expose this switch, so the setup
  script deliberately reports it as a remaining manual gate;
- restrict deployment to the release tag policy (`v*`);
- do not store product, Runtime, or Personal Model credentials in this
  environment. The only release credentials permitted are the repository
  control private key and the Apple signing/notarization secrets listed in
  `apple-signing-notarization.md`.

The Release build job is also bound to this Environment because it must access
the Developer ID certificate and notary API key only after approval. Missing
Apple material makes the build fail before it creates release assets. See
`apple-signing-notarization.md` for the exact secrets, non-secret variables,
temporary Keychain lifecycle, and rotation procedure.

The `publish` job is bound to this name and cannot run before the environment
gate is satisfied.

## Repository-control GitHub App

The workflow's ordinary `GITHUB_TOKEN` cannot read the repository
Administration setting used by immutable releases and cannot reliably expose
ruleset bypass actors. Create a dedicated GitHub App installed only on this
repository with these repository permissions:

- Administration: read and write;
- Actions: read;
- Checks: read;
- Contents: read;
- Environments: read.

The write-level Administration permission is used only by the ephemeral token
to make bypass actors visible to the live readback; the Release itself is still
created with the workflow's separate `GITHUB_TOKEN`.

Set repository variable `REPOSITORY_CONTROL_APP_CLIENT_ID` to the App client
ID. Store its private key only as the
`github-release` environment secret
`REPOSITORY_CONTROL_APP_PRIVATE_KEY`. The publish job mints a one-repository,
short-lived installation token after environment approval and revokes it at
job end. If the environment is missing and GitHub auto-creates an unprotected
one, the environment-scoped private key is absent and publication fails before
creating a Release.

The setup script stores `RELEASE_ACTOR`, `RELEASE_REVIEWER`, and
`REPOSITORY_PRIVATE_ENTERPRISE` as repository variables. The publish job uses
them to run a live `--check` immediately before release creation.

## Repository release controls

- Enable **immutable releases** before the first tag. The workflow checks the
  repository setting before creation and checks the resulting release's
  `immutable` field after publication.
- Allow GitHub Actions to grant the workflow `contents: write` for the publish
  job. All other jobs use read-only contents permission.
- Keep Issues enabled for the structured beta bug template, or replace the
  support route and template before `GO`.
- Disable unused repository features only after confirming that the product
  and support plan do not depend on them.

GitHub recommends creating an immutable release as a draft, attaching all
assets, and publishing only after the asset set is complete. `gh release
create` performs that sequence when files are supplied.

References:

- [Rules available to branch and tag rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [Repository rulesets REST API](https://docs.github.com/en/rest/repos/rules)
- [Deployment environments and required reviewers](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Deployment environments REST API](https://docs.github.com/en/rest/deployments/environments?apiVersion=2026-03-10)
- [Immutable releases](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes)
- [GitHub CLI immutable-release creation behavior](https://cli.github.com/manual/gh_release_create)

## Read-only verification

Set the final repository once, then collect these outputs as release evidence:

```bash
REPOSITORY="OWNER/REPOSITORY"

gh api \
  --header "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/${REPOSITORY}" \
  --jq '{full_name, visibility, default_branch, archived, disabled}'

gh api \
  --header "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/${REPOSITORY}/immutable-releases"

gh api \
  --header "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/${REPOSITORY}/environments/github-release" \
  --jq '{
    protection_rules,
    deployment_branch_policy
  }'

gh api \
  --header "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/${REPOSITORY}/rulesets?includes_parents=true" \
  --jq '.[] | {
    id,
    name,
    enforcement,
    source_type,
    source
  }'
```

For each returned ruleset ID, inspect its target, conditions, rules, and bypass
actors:

```bash
RULESET_ID="RETURNED_ID"
gh api \
  --header "X-GitHub-Api-Version: 2026-03-10" \
  "/repos/${REPOSITORY}/rulesets/${RULESET_ID}" \
  --jq '{
    name,
    target,
    enforcement,
    conditions,
    rules,
    bypass_actors
  }'
```

Do not change `HOLD` to `GO` when any endpoint is missing, inaccessible, or
different from the reviewed configuration.

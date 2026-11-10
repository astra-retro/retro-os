# Manual image builds

All workflows in `.github/workflows/` are manual-only. No push, PR, or
scheduled event starts an image build or GHCR cleanup.

## Test a pull request

1. Open **Actions → Build PR ISO / QCOW2 (manual)** and choose **Run workflow**.
2. Keep **Use workflow from** on `main`.
3. Enter an **open PR number targeting main**. Fork PRs are intentionally
   unsupported: the head commit must belong to `astra-retro/retro-os`.
4. Choose `both`, `iso`, or `qcow2`.
5. Download the ISO and/or QCOW2 from the workflow-run **Artifacts** section.
   ISO artifacts are retained for 3 days, QCOW2 for 7 days.

The workflow pins the PR head SHA before checkout. It builds the bootc OCI
image once from that exact commit, transfers an OCI archive to a separate job
and publishes it under `pr-<number>-<sha12>`. ISO and QCOW2 use **the exact
pushed digest** and the corresponding PR checkout for branding/build scripts.
Neither `latest` nor a version tag is modified by PR builds.

GitHub requires **write** access to the repository to start
`workflow_dispatch` manually. Administrators may further restrict who is
allowed to build by setting the repository Actions variable
`ALLOWED_BUILDERS` to a JSON array of GitHub logins, e.g.
`["maintainer-one","maintainer-two"]`. If absent, any GitHub user with
permission to manually dispatch workflows can initiate a build. An invalid
or mismatched allowlist fails the authorization step before building.

**Security:** Only the publisher job has `packages: write`. The PR checkout
and OCI build job do not receive a package-write token, registry credentials,
or signing secrets. PR builds are deliberately not signed. Only review and
run trusted internal PR changes: ISO and QCOW2 generation execute build code
from the selected PR on GitHub-hosted runners.

**Space:** The OCI image is transferred as an uncompressed GitHub Actions
artifact between the build and publisher jobs. Large images can exceed
the GitHub Actions artifact or runner storage limits.

## Manual production and maintenance operations

- **Build container image**: select `main`, manually build/publish/sign the
  normal production OCI image.
- **Build RetroOS Live ISO** and **Build RetroOS QCOW2**: select `main`,
  supply a published OCI tag (default `latest`).
- **Cleanup GHCR (Astra Retro OS)**: manually trigger cleanup. Its default
  `dry_run=true` is retained; the weekly cron was removed.

No workflows are scheduled or run automatically for pushes or pull requests.

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
and publishes it under both `pr-<number>-<sha12>` (immutable build) and
`pr-<number>` (moving PR test channel). It rechecks the PR head before
advancing `pr-<number>`: an obsolete build only publishes its immutable tag.
ISO and QCOW2 use **the exact pushed digest** and the corresponding PR
checkout for branding/build scripts. The installed OS follows the
`pr-<number>` tag for future updates. Neither `latest` nor a release tag
is modified by PR builds.

**Safety:** PR OCI images are not signed; the moving PR channel is for test
VMs only. Do not enable unattended updates on this channel.

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
  normal production OCI image; manual builds do not move `stable`.
- **Git tag release**: pushing a `vMAJOR.MINOR.PATCH` Git tag that points
  to a commit already on `main` automatically builds, signs and publishes
  the immutable version tag plus the moving `stable` tag. Other Git tag
  patterns do not publish. Version tags should never be retargeted.
- **Build RetroOS Live ISO** and **Build RetroOS QCOW2**: select `main`,
  supply a published OCI tag (default `latest`).
- **Cleanup GHCR (Astra Retro OS)**: manually trigger cleanup. Its default
  `dry_run=true` is retained; the weekly cron was removed.

No workflows are scheduled or triggered by PR updates. The only automatic
build trigger is the creation of Git release tags `vMAJOR.MINOR.PATCH`.

## Bootc update channels and existing installations

- `ghcr.io/astra-retro/retro-os:pr-N` follows new successful builds of PR N
  and should only be used in disposable test systems.
- `ghcr.io/astra-retro/retro-os:pr-N-<sha12>` is tied to one build.
- `ghcr.io/astra-retro/retro-os:vX.Y.Z` is one published release; it does
  **not** automatically advance to `vX.Y.(Z+1)`.
- `ghcr.io/astra-retro/retro-os:stable` advances only with a verified release
  built from an approved Git tag on main.
- `latest` retains its pre-existing, manually operated production behavior.

The ISO / QCOW2 scripts fetch a digest for reproducibility, but now pass a
**distinct tag** for future upgrades. On the Fedora 45 Live ISO, Anaconda uses
`bootc --source-imgref containers-storage:<digest> --target-imgref <tagged GHCR URL>`:
the source can be installed offline and the installed OS tracks the registry
tag. Kickstart's `bootc` and `ostreecontainer` directives cannot coexist.
The QCOW2 builder uses a locally tagged alias of the already-pulled digest,
so that its future update reference remains tagged rather than SHA-pinned.
Inspect the resulting installations with `bootc status` on UEFI test VMs
before considering them validated.

For **existing installations**, no reinstall is needed:

```bash
sudo bootc status
# Choose ONE channel:
sudo bootc switch ghcr.io/astra-retro/retro-os:pr-2
# OR (recommended for long-lived hosts):
sudo bootc switch ghcr.io/astra-retro/retro-os:stable
sudo bootc status
sudo reboot
sudo bootc upgrade --check
```

These commands only succeed after the respective tag has been published,
and the registry is reachable. A bootc digest may continue to appear in
`bootc status` to identify the deployed image, even when the source is
a mutable tag. `bootc rollback` is available if the new deployment fails.

**Installer consistency:** ISO and QCOW2 remain reproducible by digest,
while the future update target uses a moving tag. Do not use automatic
upgrades on an unsigned PR channel. Published tags and unpinned QCOW2
builder images must be reviewed for supply-chain safety.

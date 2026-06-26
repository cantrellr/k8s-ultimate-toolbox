# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Added

- Added SELinux and audit utilities to the toolbox image: `getenforce`, `sestatus`, `semanage`, `semodule`, `seinfo`, `sesearch`, `checkpolicy`, `checkmodule`, `audit2allow`, `audit2why`, `ausearch`, and `aureport`.
- Added `scripts/build-selinux-utils-bundle.sh` and `make selinux-bundle` to create a host-installable SELinux utilities `.deb` tarball for air-gapped environments.

### Changed

- Updated outward-facing documentation branding from `Ultimate K8s Toolbox` / `Ultimate Kubernetes Toolbox` to `K8s Ultimate Toolbox`.
- Reworked the documentation index so it points to the canonical root documentation and current `k8s-ultimate-toolbox` repository URLs.
- Replaced the stale duplicate `docs/TOOLS-REFERENCE.md` content with a compatibility pointer to the maintained root `TOOLS-REFERENCE.md` file.
- Removed the optional Keycloak CLI sidecar path from the Helm chart and documentation.
- Standardized Keycloak operations on the default `toolbox` container, which already includes `kcadm.sh`, `kcreg.sh`, `kc.sh`, and `keycloak-login.sh`.
- Updated Helm chart tests to assert that rendered and deployed workloads use a single runtime container named `toolbox`.

## [1.2.0] - 2026-06-25

### Added

- Added `crictl`, `etcdctl`, `etcdutl`, `cmctl`, `step`, `kubent`, `kubeconform`, `popeye`, `kubectl-who-can`, `rbac-lookup`, `cilium`, `hubble`, and `calicoctl`.

### Changed

- Bumped chart, app, image, and offline bundle defaults to `1.2.0` / `v1.2.0`.
- Updated Dockerfile, Makefile, README, Quick Start, SBOM notes, tools reference, offline deployment docs, and recommended-tooling roadmap for the implemented toolset.

## [1.1.0] - 2026-06-21

### Added

- PostgreSQL diagnostic tooling: `psql`, `pg_isready`, `pg_dump`, `pg_restore`, `pgbench`, `pgbadger`, `pgcli`, `pg_activity`, Python `psycopg`, and `pg-diagnostics.sh`.
- Keycloak helper script: `keycloak-login.sh`.
- Tool inventory: `TOOLS-REFERENCE.md`.
- PostgreSQL runbook: `POSTGRESQL-DIAGNOSTICS.md`.
- Keycloak operations guide: `KEYCLOAK-GUIDE.md`.
- Recommended tooling roadmap: `RECOMMENDED-TOOLS.md`.

### Changed

- Bumped chart and application version to `1.1.0`.
- Updated `kubectl` to `v1.36.1`.
- Updated Helm to `v4.2.1`.
- Updated `yq` to `v4.53.3`.
- Updated Keycloak CLI distribution to `26.6.3`.
- Updated `mongosh` to `2.8.3`.
- Updated MongoDB Database Tools to `100.17.0`.
- Updated `tridentctl` to `26.02.0`.
- Updated nerdctl build-host helper version to `2.3.2`.
- Increased default resource limits for the larger Java and PostgreSQL diagnostic stack.
- Refreshed README, Quick Start, offline deployment script template, and SBOM generation.

### Fixed

- Removed stale guidance that implied deploying a plain Ubuntu image as the toolbox.
- Added the missing `TOOLS-REFERENCE.md` file that the Makefile attempted to package.
- Corrected offline bundle script generation so generated scripts retain v1.1.0 image defaults.

## [1.0.2] - 2026-03-07

### Added

- Keycloak CLI support in toolbox image: `kcadm.sh`, `kcreg.sh`, and `kc.sh`.
- Java runtime required by Keycloak CLI tools.
- Keycloak tooling references and quick examples in docs.

### Fixed

- Dockerfile heredoc terminator for the embedded CA trust update script.

### Changed

- Release and chart version references updated to `v1.0.2` / `1.0.2`.
- Helm chart default security context aligned to the image UID/GID.

## [1.0.0] - 2025-11-26

Initial public release of K8s Ultimate Toolbox.

### Highlights

- Kubernetes administration workstation image.
- Air-gapped/offline deployment support.
- Helm chart with configurable deployment options.
- SBOM generation.
- Custom CA certificate support via init container architecture.
- Non-root container execution by default.

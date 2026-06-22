# Changelog

All notable changes to this project will be documented in this file.

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
- Updated optional Keycloak sidecar image to `quay.io/keycloak/keycloak:26.6.3`.
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

Initial public release of Ultimate K8s Toolbox.

### Highlights

- Kubernetes administration workstation image.
- Air-gapped/offline deployment support.
- Helm chart with configurable deployment options.
- SBOM generation.
- Custom CA certificate support via init container architecture.
- Non-root container execution by default.

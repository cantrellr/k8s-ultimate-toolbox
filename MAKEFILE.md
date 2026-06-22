# Makefile Documentation

The Makefile automates image builds, verification, Helm chart packaging, and air-gapped bundle creation for Ultimate K8s Toolbox v1.1.0.

## Common targets

| Target | Purpose |
|---|---|
| `make help` | Show available targets |
| `make info` | Print pinned component versions |
| `make check-dependencies` | Validate Docker or nerdctl, Helm, and curl are available |
| `make install-nerdctl` | Install nerdctl `2.3.2` helper on the build host |
| `make build-image` | Build and verify `ultimate-k8s-toolbox:v1.1.0` |
| `make test-image` | Run the built image and verify critical tools |
| `make package-chart` | Lint and package the Helm chart |
| `make offline-bundle` | Build the full offline deployment bundle |
| `make clean` | Remove generated artifacts and the local toolbox image |
| `make clean-all` | Deep clean build artifacts and runtime cache |

## Version set

```makefile
CHART_VERSION := 1.1.0
BUNDLE_VERSION := v1.1.0
KUBECTL_VERSION := v1.36.1
HELM_VERSION := v4.2.1
YQ_VERSION := v4.53.3
KEYCLOAK_VERSION := 26.6.3
MONGOSH_VERSION := 2.8.3
MONGO_TOOLS_VERSION := 100.17.0
TRIDENT_VERSION := 26.02.0
NERDCTL_VERSION := 2.3.2
CONTAINERD_VERSION := 2.3.1
```

## Build the image

```bash
make info
make build-image
```

`make build-image` passes the pinned versions into `build/Dockerfile` as build arguments and then runs `make test-image`.

## Create an offline bundle

```bash
make offline-bundle
```

Output:

```text
dist/ultimate-k8s-toolbox-offline-v1.1.0.tar.gz
```

The bundle includes:

- Toolbox image tarball and SHA256 checksum
- Packaged Helm chart
- Offline deployment script
- SBOM text and JSON
- README and runbook documentation

## Runtime selection

The Makefile prefers Docker when Docker is present and healthy. It falls back to nerdctl when Docker is unavailable. This matches mixed platform environments where developers may use Docker Desktop, while air-gapped Linux build hosts may use containerd and nerdctl.

## Validation scope

`make test-image` verifies the critical path only:

- `kubectl`
- `helm`
- `yq`
- Keycloak CLI
- PostgreSQL tooling and `pg-diagnostics.sh`
- MongoDB shell and database tools
- `tridentctl`

That is deliberate. Full end-to-end testing still requires a live cluster and target services.

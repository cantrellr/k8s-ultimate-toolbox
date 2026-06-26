# nerdctl + containerd Guide - K8s Ultimate Toolbox

K8s Ultimate Toolbox supports Docker for developer workstations and nerdctl/containerd for Kubernetes-native or air-gapped Linux build hosts.

## Why nerdctl?

- **Kubernetes-native**: containerd is the standard runtime path for many Kubernetes environments.
- **CLI-compatible**: nerdctl provides a Docker-like workflow without requiring Docker Engine.
- **Air-gap friendly**: image build, save, load, tag, and push workflows map cleanly to offline bundle handling.

## Version used by this repo

```makefile
NERDCTL_VERSION := 2.3.2
```

Run:

```bash
make info
```

## Build

```bash
make build-image
make test-image
```

## Save and load image artifacts

```bash
nerdctl --namespace k8s.io save k8s-ultimate-toolbox:v1.2.0 \
  -o k8s-ultimate-toolbox-v1.2.0.tar

nerdctl --namespace k8s.io load -i k8s-ultimate-toolbox-v1.2.0.tar
```

## Push to an internal registry

```bash
nerdctl --namespace k8s.io tag k8s-ultimate-toolbox:v1.2.0 \
  registry.example.com/library/k8s-ultimate-toolbox:v1.2.0

nerdctl --namespace k8s.io push registry.example.com/library/k8s-ultimate-toolbox:v1.2.0
```

## Reality check

Docker is still the easiest path for many desktops. nerdctl is the better enterprise-aligned path for Linux build hosts that need to stay close to Kubernetes runtime behavior.

# nerdctl + containerd Guide - K8s Ultimate Toolbox

K8s Ultimate Toolbox supports Docker for developer workstations and nerdctl/containerd for Kubernetes-native or air-gapped Linux build hosts. The Makefile prefers Docker when Docker is present and healthy, then falls back to nerdctl.

## Why nerdctl?

- **Kubernetes-native**: containerd is the standard runtime path for many Kubernetes environments.
- **CLI-compatible**: nerdctl provides a Docker-like workflow without requiring Docker Engine.
- **Air-gap friendly**: image build, save, load, tag, and push workflows map cleanly to offline bundle handling.
- **Operationally boring**: boring is good here. The runtime should not become the outage.

## Version used by this repo

```makefile
NERDCTL_VERSION := 2.3.2
CONTAINERD_VERSION := 2.3.1
```

Run:

```bash
make info
```

## Install nerdctl helper

The project Makefile can install the pinned nerdctl binary on a Linux build host:

```bash
make install-nerdctl
nerdctl version
```

## Manual Ubuntu/Debian setup

```bash
sudo apt-get update
sudo apt-get install -y containerd
sudo systemctl enable --now containerd

NERDCTL_VERSION="2.3.2"
ARCH="amd64"
curl -fsSLO "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz"
sudo tar -xzf "nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz" -C /usr/local/bin nerdctl
sudo chmod +x /usr/local/bin/nerdctl
nerdctl version
```

For ARM64, set `ARCH="arm64"`.

## Build with nerdctl

```bash
make check-dependencies
make build-image
make test-image
```

The Makefile uses the `k8s.io` containerd namespace for nerdctl operations:

```makefile
NERDCTL_NAMESPACE := k8s.io
```

## Save and load image artifacts

```bash
nerdctl --namespace k8s.io save ultimate-k8s-toolbox:v1.1.0 \
  -o ultimate-k8s-toolbox-v1.1.0.tar

nerdctl --namespace k8s.io load -i ultimate-k8s-toolbox-v1.1.0.tar
```

## Push to an internal registry

```bash
nerdctl --namespace k8s.io tag ultimate-k8s-toolbox:v1.1.0 \
  registry.example.com/library/ultimate-k8s-toolbox:v1.1.0

nerdctl --namespace k8s.io push registry.example.com/library/ultimate-k8s-toolbox:v1.1.0
```

## Reality check

Docker is still the easiest path for many desktops. nerdctl is the better enterprise-aligned path for Linux build hosts that need to stay close to Kubernetes runtime behavior. Pick the tool that reduces friction in the environment you are actually running, not the one that wins a whiteboard debate.

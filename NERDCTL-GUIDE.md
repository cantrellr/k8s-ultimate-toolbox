# nerdctl + containerd Guide

This project now uses **nerdctl** and **containerd** as the container runtime instead of Docker.

## Why nerdctl?

- **Kubernetes-native**: containerd is the default Kubernetes runtime
- **CLI-compatible**: nerdctl is a Docker-compatible CLI for containerd
- **Better integration**: Direct alignment with Kubernetes image handling
- **Future-proof**: Industry standard for container orchestration

## Installation

### Ubuntu/Debian

```bash
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Download nerdctl
NERDCTL_VERSION="1.7.6"
wget https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz
sudo tar -xzf nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin/

# Verify installation
nerdctl version
```

### macOS (via Homebrew)

```bash
brew install lima
brew install nerdctl

# Start containerd
limactl start
```

### RHEL/Rocky/AlmaLinux

```bash
sudo dnf install -y containerd
sudo systemctl enable --now containerd

# Install nerdctl
NERDCTL_VERSION="1.7.6"
wget https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz
sudo tar -xzf nerdctl-${NERDCTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin/
```

## Usage

### Makefile Commands

All Makefile commands now use nerdctl:

```bash
# Build the image
make build-image

# Test the image
make test-image

# Create offline bundle
make offline-bundle

# Clean up
make clean
```

### Manual nerdctl Commands

If you need to interact with images directly:

```bash
# List images (using k8s.io namespace)
nerdctl --namespace k8s.io images

# Run a container
nerdctl --namespace k8s.io run -it --rm ultimate-k8s-toolbox:v1.0.2 bash

# Save image for offline transfer
nerdctl --namespace k8s.io save ultimate-k8s-toolbox:v1.0.2 -o toolbox.tar

# Load image from tarball
nerdctl --namespace k8s.io load -i toolbox.tar

# Remove image
nerdctl --namespace k8s.io rmi ultimate-k8s-toolbox:v1.0.2

# System prune
nerdctl --namespace k8s.io system prune -f
```

## Namespace Configuration

This project uses the `k8s.io` namespace by default, which matches Kubernetes image handling:

```makefile
NERDCTL_NAMESPACE := k8s.io
```

### Why k8s.io namespace?

- **Kubernetes compatibility**: Images built in k8s.io namespace are directly accessible to Kubernetes
- **Isolation**: Separates Kubernetes images from other containerd images
- **Best practice**: Standard namespace for Kubernetes-related images

## Differences from Docker

### Command Comparison

| Docker | nerdctl |
|--------|---------|
| `docker build -t img .` | `nerdctl --namespace k8s.io build -t img .` |
| `docker run -it img` | `nerdctl --namespace k8s.io run -it img` |
| `docker save img -o img.tar` | `nerdctl --namespace k8s.io save img -o img.tar` |
| `docker load -i img.tar` | `nerdctl --namespace k8s.io load -i img.tar` |
| `docker images` | `nerdctl --namespace k8s.io images` |
| `docker rmi img` | `nerdctl --namespace k8s.io rmi img` |

### Key Differences

1. **Namespace requirement**: Must specify `--namespace` for isolation
2. **CNI plugins**: Network setup requires CNI plugins (usually pre-installed with K8s)
3. **BuildKit**: Uses containerd's native BuildKit (faster builds)
4. **Registry auth**: Uses Docker-compatible config at `~/.docker/config.json`

## Troubleshooting

### "nerdctl: command not found"

```bash
# Check if nerdctl is installed
which nerdctl

# If not installed, follow installation instructions above
```

### Permission Denied

```bash
# Add user to containerd group
sudo usermod -aG containerd $USER

# Or run with sudo
sudo make build-image
```

### Images Not Visible in Kubernetes

```bash
# Verify you're using k8s.io namespace
nerdctl --namespace k8s.io images

# If image is in wrong namespace, re-tag it:
nerdctl --namespace default images  # Check default namespace
nerdctl --namespace default tag img:tag img:tag
nerdctl --namespace k8s.io save img:tag | nerdctl --namespace k8s.io load
```

### Build Failures

```bash
# Clear build cache
nerdctl --namespace k8s.io system prune -a -f

# Rebuild from scratch
make clean
make build-image
```

## Migration from Docker

If you were previously using Docker:

### 1. Export Existing Images

```bash
# With Docker
docker save ultimate-k8s-toolbox:v1.0.2 -o toolbox.tar

# Load into nerdctl
nerdctl --namespace k8s.io load -i toolbox.tar
```

### 2. Update Scripts

Replace all `docker` commands with `nerdctl --namespace k8s.io`:

```bash
# Before
docker build -t myimage .
docker run -it myimage

# After
nerdctl --namespace k8s.io build -t myimage .
nerdctl --namespace k8s.io run -it myimage
```

### 3. Verify Kubernetes Access

```bash
# Check if K8s can see the image
kubectl run test --image=ultimate-k8s-toolbox:v1.0.2 --dry-run=client -o yaml
```

## Best Practices

### 1. Always Use k8s.io Namespace

```bash
# Set alias for convenience
alias nerdctl='nerdctl --namespace k8s.io'
```

### 2. Use Makefile Targets

Prefer using Makefile targets instead of manual commands:
```bash
make build-image  # Instead of manual nerdctl build
make clean        # Clean up properly
```

### 3. Registry Configuration

For offline registries, configure nerdctl mirrors:

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.com"]
    endpoint = ["https://harbor.internal.com"]
```

### 4. Rootless Mode

For enhanced security, consider using nerdctl in rootless mode:

```bash
containerd-rootless-setuptool.sh install
nerdctl --namespace k8s.io images
```

## Additional Resources

- **nerdctl GitHub**: https://github.com/containerd/nerdctl
- **containerd docs**: https://containerd.io/docs/
- **Kubernetes CRI**: https://kubernetes.io/docs/concepts/architecture/cri/

## Support

For issues specific to nerdctl/containerd:
1. Check `nerdctl info` for system information
2. Review containerd logs: `journalctl -u containerd -f`
3. Verify CNI plugins: `ls /opt/cni/bin/`

# SELinux Utilities and Air-Gap Bundle Guide

K8s Ultimate Toolbox includes SELinux and audit utilities in the default toolbox image and also provides a separate host-installable offline bundle workflow for air-gapped Ubuntu/Debian systems.

## Toolbox image utilities

The toolbox image installs package-managed SELinux and audit utilities, including:

- `getenforce`
- `sestatus`
- `semanage`
- `semodule`
- `seinfo`
- `sesearch`
- `checkpolicy`
- `checkmodule`
- `audit2allow`
- `audit2why`
- `ausearch`
- `aureport`

Validate inside the toolbox pod:

```bash
show-versions.sh
command -v getenforce sestatus semanage semodule seinfo sesearch checkpolicy checkmodule audit2allow audit2why ausearch aureport
```

## Common diagnostics

```bash
getenforce
sestatus
semanage boolean -l
semodule -l
seinfo
sesearch --allow -s container_t 2>/dev/null | head
audit2allow --help
audit2why --help
ausearch --help
aureport --help
```

Some commands depend on the host kernel, mounted policy store, audit logs, and SELinux status. In a container, these tools are primarily useful for inspecting copied policy files, mounted audit logs, and troubleshooting evidence collected from nodes.

## Build an offline SELinux utilities tarball

Run this on an internet-connected Ubuntu/Debian host that matches the target OS family, release codename, and architecture:

```bash
make selinux-bundle
```

The generated tarball is written to:

```text
dist/selinux-utils-bundle/*.tar.gz
```

The tarball includes:

- `debs/*.deb`
- `install-selinux-utils.sh`
- `README.md`
- `manifest.txt`
- `SHA256SUMS`

## Install on the air-gapped target

Copy the tarball to the target system, then run:

```bash
tar -xzf selinux-utils-*.tar.gz
./install-selinux-utils.sh
```

The installer uses the bundled local `.deb` files. No internet access should be required when the bundle was built against the matching target release and architecture.

## Custom package list

You can pass package names directly to the builder when you need to add or remove utilities:

```bash
./scripts/build-selinux-utils-bundle.sh selinux-utils policycoreutils policycoreutils-python-utils checkpolicy setools auditd
```

The script resolves dependencies with `apt-cache depends --recurse`, downloads the package set with `apt-get download`, writes a manifest, and packages everything into a copyable tarball.

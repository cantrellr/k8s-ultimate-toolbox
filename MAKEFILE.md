# Makefile Documentation

Current artifact name: `k8s-ultimate-toolbox`.

Current release: `v1.2.0`.

Primary commands:

```bash
make info
make build-image
make test-image
make package-chart
make offline-bundle
make selinux-bundle
```

Expected toolbox bundle:

```text
dist/k8s-ultimate-toolbox-offline-v1.2.0.tar.gz
```

Expected SELinux utilities bundle:

```text
dist/selinux-utils-bundle/*.tar.gz
```

`make selinux-bundle` runs `scripts/build-selinux-utils-bundle.sh`, which downloads SELinux utility `.deb` packages and dependencies into a host-installable air-gap tarball.

# K8s Ultimate Toolbox - Agent Instructions

## Project Overview

This repository contains **K8s Ultimate Toolbox**, a Kubernetes administration workstation image and Helm chart.

Current artifact names:

```text
Repository: cantrellr/k8s-ultimate-toolbox
Chart:      k8s-ultimate-toolbox
Image:      k8s-ultimate-toolbox:v1.2.0
Deployment: <release>-k8s-ultimate-toolbox
```

## Repository Structure

```text
k8s-ultimate-toolbox/
├── Makefile
├── README.md
├── QUICKSTART.md
├── QUICK-REFERENCE.md
├── TOOLS-REFERENCE.md
├── OFFLINE-DEPLOYMENT.md
├── MAKEFILE.md
├── SBOM.md
├── build/
│   └── Dockerfile
├── chart/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── examples/
├── scripts/
└── tests/
```

## Common Tasks

```bash
make info
make build-image
make test-image
make offline-bundle

helm upgrade --install toolbox ./chart -n toolbox --create-namespace
kubectl -n toolbox exec -it deploy/toolbox-k8s-ultimate-toolbox -- bash
```

## Helm helper namespace

All Helm helpers use the `k8s-ultimate-toolbox.*` namespace.

The image helper is:

```text
k8s-ultimate-toolbox.image
```

Keep chart names, image names, helper names, labels, examples, scripts, docs, and workflows aligned to the current `k8s-ultimate-toolbox` spelling.

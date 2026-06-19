# Contributing to Ultimate K8s Toolbox

First off, thank you for considering contributing to Ultimate K8s Toolbox! ✈️

This project aims to be the most comprehensive Kubernetes administration toolkit available, and contributions from the community help make it better for everyone.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Adding New Tools](#adding-new-tools)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Style Guidelines](#style-guidelines)
- [Commit Messages](#commit-messages)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When creating a bug report, include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (commands, configuration files)
- **Describe the behavior you observed and what you expected**
- **Include environment details:**
  - Kubernetes version (`kubectl version`)
  - Helm version (`helm version`)
  - Container runtime (Docker/containerd/nerdctl)
  - Operating system

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear and descriptive title**
- **Provide a detailed description** of the suggested enhancement
- **Explain why this enhancement would be useful**
- **Include examples** of how the feature would be used

### Adding New Tools

Want to add a new tool to the toolbox? Great! Here's how:

1. **Check if the tool already exists** - Review the [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md)
2. **Ensure the tool is useful** for Kubernetes administration or related tasks
3. **Update the Dockerfile** in `build/Dockerfile`:
   - Add the tool in the appropriate section (categorized by purpose)
   - Include version pinning where possible
   - Add clear comments explaining the tool's purpose
4. **Update documentation**:
   - Add entry to `TOOLS-REFERENCE.md` with examples
   - Update tool count in `README.md`
5. **Test the build** - Run `make build` and verify the tool works

### Pull Requests

1. **Fork the repo** and create your branch from `main`
2. **Make your changes** following our style guidelines
3. **Test your changes** thoroughly
4. **Update documentation** if needed
5. **Submit a pull request** with a clear description

## Development Setup

### Prerequisites

- Docker or nerdctl/containerd
- Helm 3.x
- kubectl
- Make

### Building Locally

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/ultimate-k8s-toolbox.git
cd ultimate-k8s-toolbox

# Build the image
make build

# Run tests
make test

# Build for multiple architectures
make build-multi
```

### Testing Changes

```bash
# Deploy to a test cluster
helm upgrade --install test-toolbox ./chart -n test --create-namespace

# Exec into the pod
./scripts/toolbox test

# Run the test suite
./tests/test-helm-chart.sh
```

## Style Guidelines

### Dockerfile

- Group related installations together
- Add comments explaining each tool's purpose
- Use specific version tags where possible
- Clean up package manager caches

```dockerfile
# GOOD
# Install network debugging tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl=7.88.* \
    wget=1.21.* \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# BAD
RUN apt-get install curl wget netcat
```

### Helm Templates

- Use helper templates from `_helpers.tpl`
- Add YAML comments for complex logic
- Follow Kubernetes naming conventions

### Shell Scripts

- Use `#!/bin/bash` shebang
- Add `set -e` for error handling
- Include usage comments at the top
- Quote variables: `"$VAR"` not `$VAR`

### Documentation

- Use Markdown formatting consistently
- Include code examples with proper syntax highlighting
- Keep lines under 100 characters when possible
- Update table of contents when adding sections

## Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring without behavior change
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(dockerfile): add trivy vulnerability scanner

fix(chart): correct init container security context

docs(readme): update tool count and add architecture diagram

chore(makefile): add SBOM generation target
```

## Recognition

Contributors will be recognized in our [CHANGELOG](CHANGELOG.md) and release notes. Significant contributions may also be highlighted in the README.

---

Thank you for helping make Ultimate K8s Toolbox better! 🚀

*"Per aspera ad astra"* - Through hardships to the stars

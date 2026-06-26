# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 1.2.x | :white_check_mark: |
| 1.1.x | :white_check_mark: |
| 1.0.x | :white_check_mark: |

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Use GitHub private vulnerability reporting:

https://github.com/cantrellr/k8s-ultimate-toolbox/security/advisories/new

## Security Best Practices

When using K8s Ultimate Toolbox, treat the pod as operational tooling. Deploy it only into approved namespaces, scope service accounts carefully, and remove it when troubleshooting is complete.

### Network policy selector

```yaml
podSelector:
  matchLabels:
    app.kubernetes.io/name: k8s-ultimate-toolbox
```

### Secrets Management

- Never commit secrets to the repository.
- Use Kubernetes Secrets or external secret management.
- Rotate credentials regularly.
- Use short-lived tokens when possible.

## Security Updates

Security updates are released as patch versions and announced via GitHub Releases, Security Advisories, and CHANGELOG.md.

Thank you for helping keep K8s Ultimate Toolbox and its users safe.

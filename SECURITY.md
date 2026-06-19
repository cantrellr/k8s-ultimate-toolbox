# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### How to Report

**Please DO NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via one of the following methods:

1. **GitHub Security Advisories**: Use GitHub's private vulnerability reporting feature at:
   https://github.com/cantrellr/ultimate-k8s-toolbox/security/advisories/new

2. **Email**: Send details to the repository owner (check profile for contact information)

### What to Include

Please include the following information in your report:

- **Type of vulnerability** (e.g., container escape, privilege escalation, information disclosure)
- **Location** of the vulnerability (file path, container layer, Helm values)
- **Step-by-step instructions** to reproduce the issue
- **Proof of concept** if available
- **Impact assessment** of the vulnerability
- **Suggested fix** if you have one

### Response Timeline

- **Initial Response**: Within 48 hours of your report
- **Status Update**: Within 7 days with our assessment
- **Fix Timeline**: Critical vulnerabilities within 14 days, others within 30 days

### What to Expect

1. **Acknowledgment**: We'll acknowledge receipt of your report
2. **Assessment**: We'll investigate and assess the severity
3. **Communication**: We'll keep you informed of our progress
4. **Resolution**: We'll develop and test a fix
5. **Disclosure**: We'll coordinate disclosure timing with you
6. **Credit**: We'll credit you in our release notes (unless you prefer anonymity)

## Security Best Practices

When using the Ultimate K8s Toolbox, we recommend the following security practices:

### Container Security

```yaml
# Use non-root user (enabled by default)
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: false  # Required for some tools
  allowPrivilegeEscalation: false
```

### RBAC Configuration

```yaml
# Grant minimal required permissions
rbac:
  create: true
  clusterRole: true  # Set to false if cluster-wide access not needed
```

### Network Policies

Consider implementing NetworkPolicies to restrict the toolbox pod's network access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: toolbox-network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ultimate-k8s-toolbox
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}  # Cluster internal only
```

### Air-Gapped Deployments

For maximum security in air-gapped environments:

1. **Verify image signatures** when importing
2. **Use SBOM** to audit all included packages
3. **Scan for vulnerabilities** before deployment
4. **Use custom CA certificates** for internal registries

### Secrets Management

- Never commit secrets to the repository
- Use Kubernetes Secrets or external secret management
- Rotate credentials regularly
- Use short-lived tokens when possible

## Known Security Considerations

### Container Capabilities

The toolbox runs as a non-root user by default but may require certain capabilities for specific tools:

| Tool | Capability | Reason |
|------|------------|--------|
| tcpdump | CAP_NET_RAW | Packet capture |
| ping | CAP_NET_RAW | ICMP packets |
| nmap | CAP_NET_RAW | Network scanning |

These capabilities are NOT granted by default. If needed, explicitly configure them:

```yaml
securityContext:
  capabilities:
    add: ["NET_RAW"]
```

### Volume Mounts

Be cautious when mounting host paths or sensitive volumes into the toolbox:

```yaml
# Avoid mounting sensitive host paths unless necessary
volumes:
  # RISKY: Host filesystem access
  - name: host-root
    hostPath:
      path: /
```

## Vulnerability Disclosure Policy

We follow a coordinated vulnerability disclosure process:

1. **90-day disclosure deadline**: After 90 days, we may publicly disclose the vulnerability regardless of fix status
2. **Earlier disclosure**: If a fix is available and deployed, we may disclose earlier
3. **Extended timeline**: For complex issues, we may extend the timeline with researcher agreement

## Security Updates

Security updates are released as patch versions (e.g., 1.0.2, 1.0.3) and announced via:

- GitHub Releases
- Security Advisories
- CHANGELOG.md

## Contact

For security-related inquiries that don't involve vulnerability reports, please open a GitHub issue with the `security` label.

---

Thank you for helping keep Ultimate K8s Toolbox and its users safe!

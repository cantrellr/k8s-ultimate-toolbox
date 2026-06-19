# Software Bill of Materials (SBOM)

## Overview

The Ultimate K8s Toolbox automatically generates a comprehensive Software Bill of Materials (SBOM) for every offline bundle. The SBOM provides complete transparency into all software components, their versions, licenses, and cryptographic hashes for verification.

## SBOM Formats

The offline bundle includes two SBOM formats:

### 1. SBOM.txt (Human-Readable)
- **Format**: SPDX-like text format
- **Purpose**: Easy to read and audit
- **Contents**: Detailed component listing with versions, licenses, and SHA256 hashes
- **Use Case**: Manual review, compliance documentation

### 2. SBOM.json (Machine-Readable)
- **Format**: CycloneDX 1.4
- **Purpose**: Automated processing and integration
- **Contents**: Structured JSON with component metadata and cryptographic hashes
- **Use Case**: CI/CD pipelines, security scanning tools, compliance automation

## SHA256 Hash Verification

The SBOM includes SHA256 hashes for critical artifacts to ensure supply chain integrity:

### Artifact Hashes
| Artifact | Hash Location | Purpose |
|----------|---------------|---------|
| Container Image | `image_digest` field | Verify image integrity |
| Image Tarball | `tarball_hash` field | Verify exported image file |
| Helm Chart | `chart_hash` field | Verify chart package |

### Example Hash Entries (SBOM.txt)
```
=== ARTIFACT HASHES ===
Image Digest: sha256:a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4
Image Tarball SHA256: <IMAGE_TARBALL_SHA256>
Helm Chart SHA256: <CHART_TGZ_SHA256>

=== VERIFICATION COMMANDS ===
# Verify image tarball
sha256sum -c <<< "<IMAGE_TARBALL_SHA256>  images/ultimate-k8s-toolbox-v1.0.2.tar"

# Verify Helm chart
sha256sum -c <<< "<CHART_TGZ_SHA256>  charts/ultimate-k8s-toolbox-chart-1.0.2.tgz"
```

### CycloneDX JSON Hash Format
```json
{
  "metadata": {
    "properties": [
      { "name": "image_digest", "value": "sha256:..." },
      { "name": "tarball_hash", "value": "sha256:..." },
      { "name": "chart_hash", "value": "sha256:..." }
    ]
  }
}
```

## What's Included

The SBOM catalogs all components in the toolbox:

### Container Images
- Base OS (Ubuntu 24.04 LTS)
- Toolbox image with all tools

### MongoDB Tools (2 components)
- MongoDB Shell (mongosh)
- MongoDB Database Tools suite

### Kubernetes Tools (3 components)
- kubectl
- Helm
- yq

### Storage Tools (2 components)
- tridentctl (NetApp Trident)
- NFS client utilities

### Networking Tools (13 components)
- curl, wget, netcat, nmap
- DNS utilities (dig, nslookup)
- IP tools (ip, ss, netstat, ifconfig)
- Diagnostic tools (ping, traceroute, tcpdump)
- Connection tools (socat, telnet, SSH)

### Python Environment (7 components)
- Python 3.12 runtime
- pymongo, kubernetes, PyYAML
- requests, jinja2, click

### System Tools (10 components)
- Editors (vim, nano)
- Monitoring (htop, sysstat)
- Processing (jq, yq)
- Debugging (strace, lsof, tmux)
- Shell enhancements (bash-completion)
- Security (ca-certificates)

### Helm Chart
- Ultimate K8s Toolbox deployment chart

### Build Tools (not in final image)
- nerdctl
- containerd

## License Summary

The SBOM includes license information for all components:

| License | Count | Examples |
|---------|-------|----------|
| Apache-2.0 | 11 | kubectl, mongosh, Helm, tridentctl |
| GPL-2.0 | 7 | htop, nmap, iproute2 |
| BSD | 5 | netcat, ping, tcpdump, openssh |
| MIT | 4 | curl, yq, jq, PyYAML |
| GPL-3.0 | 2 | wget, nano |
| Other | 11 | Python, vim, tmux, etc. |

**Total Components**: 40 (38 in image, 2 build-only)

## Location

After running `make offline-bundle`, the SBOM files are located at:

```
dist/offline-bundle/
├── SBOM.txt          # Human-readable format
└── SBOM.json         # CycloneDX JSON format
```

Both files are included in the final tarball:
```
dist/ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
└── offline-bundle/
    ├── SBOM.txt
    └── SBOM.json
```

## Usage Examples

### Review SBOM Manually
```bash
# Extract and view text SBOM
tar -xzf ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
cat offline-bundle/SBOM.txt
```

### Parse SBOM Programmatically
```bash
# Extract component versions from JSON
jq '.components[] | select(.name=="kubectl") | .version' offline-bundle/SBOM.json

# List all Apache-2.0 licensed components
jq '.components[] | select(.licenses[0].license.id=="Apache-2.0") | .name' offline-bundle/SBOM.json

# Count components by license
jq -r '.components[].licenses[0].license.id' offline-bundle/SBOM.json | sort | uniq -c
```

### Integrate with Security Tools
```bash
# Use with dependency scanning tools
grype sbom:offline-bundle/SBOM.json

# Check for CVEs
trivy sbom offline-bundle/SBOM.json

# Validate with SBOM validators
cyclonedx-cli validate --input-file offline-bundle/SBOM.json
```

## Compliance Use Cases

### Security Audits
- Identify all software components and versions
- Track known vulnerabilities (CVEs)
- Verify approved software lists

### License Compliance
- Review all licenses before deployment
- Ensure GPL compliance requirements
- Identify proprietary components

### Supply Chain Security
- Document complete software supply chain
- Track provenance of components
- Verify checksums in MANIFEST.txt

### Change Management
- Compare SBOMs between versions
- Track component additions/removals
- Audit version updates

## SBOM Standards

The toolbox SBOM follows industry standards:

### Text Format
- Based on SPDX (Software Package Data Exchange)
- Human-readable structure
- Clear component categorization

### JSON Format
- CycloneDX 1.4 specification
- Industry-standard format
- Compatible with OWASP tools

### Package URLs (PURLs)
Where applicable, components include PURLs:
```
pkg:github/kubernetes/kubernetes@v1.31.4
pkg:pypi/pymongo
pkg:github/mongodb-js/mongosh@2.3.7
```

## Updating SBOM

The SBOM is automatically generated during bundle creation. To update:

1. Update tool versions in `build/Dockerfile`
2. Update version references in Makefile `create-sbom` target
3. Run `make offline-bundle`
4. New SBOM files are generated with current versions

## Verification

The SBOM can be verified against the actual bundle:

```bash
# Verify image tarball hash (from SBOM.txt)
grep "Image Tarball SHA256" dist/offline-bundle/SBOM.txt
sha256sum dist/offline-bundle/images/*.tar

# Verify Helm chart hash
grep "Helm Chart SHA256" dist/offline-bundle/SBOM.txt
sha256sum dist/offline-bundle/charts/*.tgz

# Cross-reference with MANIFEST.txt checksums
sha256sum -c dist/offline-bundle/MANIFEST.txt

# Check image digest after loading
docker load -i dist/offline-bundle/images/*.tar
docker inspect ultimate-k8s-toolbox:v1.0.2 --format='{{.Id}}'

# Verify component presence in image
docker run --rm ultimate-k8s-toolbox:v1.0.2 bash -c "
  mongosh --version
  kubectl version --client
  python3 --version
"
```

### Programmatic Hash Verification
```bash
# Extract and verify hashes from CycloneDX JSON
IMAGE_HASH=$(jq -r '.metadata.properties[] | select(.name=="tarball_hash") | .value' offline-bundle/SBOM.json)
CHART_HASH=$(jq -r '.metadata.properties[] | select(.name=="chart_hash") | .value' offline-bundle/SBOM.json)

# Verify image tarball
echo "${IMAGE_HASH}  images/ultimate-k8s-toolbox-v1.0.2.tar" | sha256sum -c -

# Verify chart
echo "${CHART_HASH}  charts/ultimate-k8s-toolbox-chart-1.0.2.tgz" | sha256sum -c -
```

## Best Practices

### Regular Updates
- Regenerate SBOM with each release
- Track component version changes
- Document security patches

### Version Control
- Commit SBOM files to git
- Tag releases with matching SBOMs
- Maintain SBOM history

### Distribution
- Include SBOM in all distributions
- Make SBOM publicly accessible
- Provide SBOM before deployment

### Automation
- Integrate SBOM generation in CI/CD
- Automatically scan for vulnerabilities
- Alert on license violations

## Additional Resources

- [SPDX Specification](https://spdx.dev/)
- [CycloneDX Standard](https://cyclonedx.org/)
- [OWASP Dependency Track](https://dependencytrack.org/)
- [NTIA SBOM Minimum Elements](https://www.ntia.gov/sbom)

## Support

For questions about the SBOM:
- Review the SBOM.txt file for component details
- Check component documentation in docs/
- See TOOLS-REFERENCE.md for tool descriptions
- Refer to MANIFEST.txt for checksums

---

**Note**: The SBOM is automatically generated and should not be manually edited. All component information is derived from the build process and Dockerfile specifications.

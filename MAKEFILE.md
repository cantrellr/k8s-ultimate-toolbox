# Makefile Documentation

## Overview

The Makefile provides an automated workflow for creating offline deployment bundles of the Ultimate K8s Toolbox Helm chart. It handles internet connectivity checks, image downloads, chart packaging, and bundle creation.

## Quick Start

### Create Offline Bundle

```bash
make offline-bundle
```

This single command will:
1. ✅ Check internet connectivity
2. ✅ Prepare bundle directories
3. ✅ Pull and export Docker images
4. ✅ Package Helm chart
5. ✅ Create deployment scripts
6. ✅ Generate compressed tarball

### Output

The command creates:
```
ultimate-k8s-toolbox-offline-v1.0.2.tar.gz  (~29MB)
```

## Configuration

Edit the Makefile to customize:

```makefile
# Chart configuration
CHART_NAME := ultimate-k8s-toolbox
CHART_VERSION := 1.0.2
BUNDLE_VERSION := v1.0.2

# Image configuration
TOOLBOX_IMAGE_REPO := ultimate-k8s-toolbox
TOOLBOX_IMAGE_TAG := v1.0.2
```

## Available Commands

### Primary Commands

| Command | Description |
|---------|-------------|
| `make offline-bundle` | Create complete offline bundle |
| `make help` | Show help information |
| `make info` | Display configuration |
| `make clean` | Remove generated files |

### Individual Steps

| Command | Description |
|---------|-------------|
| `make check-internet` | Verify internet connectivity |
| `make prepare-bundle` | Create bundle directories |
| `make pull-images` | Pull and export Docker images |
| `make package-chart` | Package Helm chart |
| `make create-scripts` | Generate deployment scripts |
| `make bundle-archive` | Create final tarball |

## Bundle Contents

The offline bundle contains:

```
offline-bundle/
├── images/
│   └── ultimate-k8s-toolbox-v1.0.2.tar    (Docker image)
├── charts/
│   └── ultimate-k8s-toolbox-chart-1.0.2.tgz     (Helm chart)
├── scripts/
│   └── deploy-offline.sh                   (Deployment script)
├── README.txt                              (Quick start guide)
└── MANIFEST.txt                            (File checksums)
```

## Prerequisites

### On Source Machine (with Internet)

- Docker installed and running
- Helm 3.0+
- curl
- tar
- Make
- Internet access

### Installation Commands

```bash
# Docker (if not installed)
curl -fsSL https://get.docker.com | sh

# Helm (if not installed)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Usage Examples

### Example 1: Basic Bundle Creation

```bash
# Clean any previous bundles
make clean

# Create new bundle
make offline-bundle

# Output:
# ✓ Bundle created: ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
# -rw-r--r-- 1 user user 29M Nov 24 13:42 ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
```

### Example 2: Custom Image

Edit Makefile:

```makefile
# Use your actual toolbox image
TOOLBOX_IMAGE_REPO := mycompany/ultimate-k8s-toolbox
TOOLBOX_IMAGE_TAG := v2.0.0
```

Then run:

```bash
make offline-bundle
```

### Example 3: Check Configuration

```bash
make info
```

Output:

```
Chart: ultimate-k8s-toolbox v1.0.2
Bundle: v1.0.2
Image: ultimate-k8s-toolbox:v1.0.2
```

### Example 4: Step-by-Step Execution

```bash
# Run each step individually
make check-internet
make prepare-bundle
make pull-images
make package-chart
make create-scripts
make bundle-archive
```

## Deployment Workflow

### On Source Machine (Online)

1. **Create Bundle:**
   ```bash
   cd /path/to/ultimate-k8s-toolbox
   make offline-bundle
   ```

2. **Transfer Bundle:**
   ```bash
   # Copy to USB drive
   cp ultimate-k8s-toolbox-offline-v1.0.2.tar.gz /media/usb/

   # Or transfer via approved method
   scp ultimate-k8s-toolbox-offline-v1.0.2.tar.gz user@offline-host:/tmp/
   ```

### On Target Machine (Offline)

1. **Extract Bundle:**
   ```bash
   tar -xzf ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
   cd offline-bundle
   ```

2. **Review Contents:**
   ```bash
   cat README.txt
   cat MANIFEST.txt
   ls -lh images/ charts/ scripts/
   ```

3. **Deploy:**
   ```bash
   cd scripts
   
   # Set environment variables (optional)
   export REGISTRY="myregistry.local:5000"
   export NAMESPACE="toolbox"
   export RELEASE_NAME="my-toolbox"
   
   # Run deployment
   ./deploy-offline.sh
   ```

## Troubleshooting

### No Internet Connection

**Problem:**
```
Checking internet connectivity...
✗ No internet
make: *** [check-internet] Error 1
```

**Solution:**
- Ensure you're on a machine with internet access
- Check firewall/proxy settings
- Try: `curl -v https://registry-1.docker.io`

### Docker Permission Denied

**Problem:**
```
permission denied while trying to connect to docker API
```

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or use sudo
sudo make offline-bundle
```

### Chart Lint Fails

**Problem:**
```
Error: 1 chart(s) linted, 1 chart(s) failed
```

**Solution:**
- Review chart files for errors
- Check `values.yaml` syntax
- Ensure templates are valid
- Run: `helm lint . --debug`

### Image Pull Fails

**Problem:**
```
Error response from daemon: manifest not found
```

**Solution:**
- Verify image name and tag are correct
- Check Docker Hub or registry availability
- Try pulling image manually: `docker pull ubuntu:24.04`

## Customization

### Adding Additional Images

Edit Makefile and add to `pull-images` target:

```makefile
.PHONY: pull-images
pull-images:
	@echo "Pulling images..."
	@docker pull $(TOOLBOX_IMAGE)
	@docker pull mongo:7.0
	@docker pull busybox:latest
	@docker save $(TOOLBOX_IMAGE) -o $(IMAGES_DIR)/toolbox.tar
	@docker save mongo:7.0 -o $(IMAGES_DIR)/mongo.tar
	@docker save busybox:latest -o $(IMAGES_DIR)/busybox.tar
	@echo "✓ Images exported"
```

### Custom Bundle Name

```makefile
BUNDLE_VERSION := v2.0.0-prod
```

### Different Chart Version

```makefile
CHART_VERSION := 0.2.0
```

## Advanced Usage

### Verifying Bundle Integrity

```bash
# Extract and check checksums
tar -xzf ultimate-k8s-toolbox-offline-v1.0.2.tar.gz
cd offline-bundle
grep ".tar\|.tgz" MANIFEST.txt | while read sum file; do
  echo "$sum $file" | sha256sum -c -
done
```

### Automating Bundle Creation

Create a script:

```bash
#!/bin/bash
# create-bundle.sh

set -e

cd /path/to/ultimate-k8s-toolbox

# Update version
sed -i "s/^BUNDLE_VERSION :=.*/BUNDLE_VERSION := v$(date +%Y%m%d)/" Makefile

# Create bundle
make clean
make offline-bundle

# Upload to artifact repository
# aws s3 cp ultimate-k8s-toolbox-offline-*.tar.gz s3://my-bucket/
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Create Offline Bundle

on:
  release:
    types: [published]

jobs:
  build-bundle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      
      - name: Create bundle
        run: |
          cd ultimate-k8s-toolbox
          make offline-bundle
      
      - name: Upload bundle
        uses: actions/upload-artifact@v3
        with:
          name: offline-bundle
          path: ultimate-k8s-toolbox/ultimate-k8s-toolbox-offline-*.tar.gz
```

## Performance Tips

1. **Use Docker Layer Caching:**
   - Images already pulled won't be re-downloaded
   - Speeds up repeated bundle creation

2. **Parallel Operations:**
   - The Makefile executes steps sequentially for reliability
   - For advanced users, steps can be parallelized if needed

3. **Bundle Size Optimization:**
   - Use smaller base images where possible
   - Consider multi-stage builds for custom toolbox images
   - Compress with maximum compression: `tar -czf` (already used)

## Security Considerations

1. **Image Verification:**
   - Always verify image sources
   - Check SHA256 sums in MANIFEST.txt
   - Use signed images when available

2. **Bundle Integrity:**
   - Transfer bundles over secure channels
   - Verify checksums after transfer
   - Store bundles in secure locations

3. **Access Control:**
   - Restrict who can create bundles
   - Control access to internal registries
   - Audit bundle deployments

## Best Practices

1. **Version Everything:**
   - Tag bundle versions clearly
   - Match bundle versions to toolbox versions
   - Document changes between versions

2. **Test Before Distribution:**
   - Always test bundles in a staging environment
   - Verify all components work offline
   - Document any issues encountered

3. **Maintain Documentation:**
   - Keep README.txt updated
   - Document deployment procedures
   - Include troubleshooting steps

4. **Automate Regular Updates:**
   - Schedule bundle creation
   - Update base images regularly
   - Keep Helm charts current

## Support

For issues or questions:

1. Check `TEST-RESULTS.md` for validation info
2. Review `OFFLINE-DEPLOYMENT.md` for detailed deployment guide
3. See `README.md` for chart documentation
4. Check `QUICKSTART.md` for quick reference

## License

MIT

---

**Version:** 1.0.2  
**Last Updated:** March 7, 2026  
**Makefile Version:** 1.0

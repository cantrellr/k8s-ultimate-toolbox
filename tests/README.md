# Tests

This directory contains testing scripts and validation results for the Ultimate K8s Toolbox Helm chart.

## Files

### test-helm-chart.sh
Automated test suite that validates the Helm chart functionality.

**Features:**
- Chart linting validation
- Template rendering tests for multiple scenarios
- Online deployment test
- Offline configuration test
- Pod functionality verification
- Namespace override testing

**Usage:**
```bash
./test-helm-chart.sh
```

**Requirements:**
- helm 3.0+
- kubectl with cluster access
- Test namespace permission

### TEST-RESULTS.md
Documentation of test execution results including:
- Test environment details
- All test cases executed
- Pass/fail status for each test
- Sample output and validation results
- Known issues and limitations

## Running Tests

### Quick Test (Lint Only)
```bash
cd ..
helm lint chart/
```

### Template Rendering Test
```bash
cd ..
helm template test-release chart/ -f examples/values-online.yaml
helm template test-release chart/ -f examples/values-offline.yaml
```

### Full Test Suite
```bash
./test-helm-chart.sh
```

### Manual Deployment Test
```bash
cd ..
# Deploy to test namespace
helm install toolbox-test chart/ --set image.repository=ubuntu --set image.tag=24.04 -n toolbox-test --create-namespace

# Verify deployment
kubectl get pods -n toolbox-test
kubectl exec -n toolbox-test -it deploy/toolbox-test-ultimate-k8s-toolbox -- bash

# Cleanup
helm uninstall toolbox-test -n toolbox-test
kubectl delete namespace toolbox-test
```

## Test Coverage

- ✅ Chart structure validation
- ✅ values.yaml defaults
- ✅ Online deployment (Docker Hub)
- ✅ Offline deployment (internal registry)
- ✅ Namespace override
- ✅ Service account creation
- ✅ Service account reuse
- ✅ Image resolution logic
- ✅ Environment variable injection
- ✅ Resource limits
- ✅ Security contexts
- ✅ Pod execution

## CI/CD Integration

The test script can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Test Helm Chart
  run: |
    cd tests
    ./test-helm-chart.sh
```

```yaml
# GitLab CI example
test:
  script:
    - cd tests
    - ./test-helm-chart.sh
```

## See Also

- [TEST-RESULTS.md](TEST-RESULTS.md) - Detailed test results
- [README.md](../README.md) - Main documentation
- [QUICKSTART.md](../QUICKSTART.md) - Quick deployment guide

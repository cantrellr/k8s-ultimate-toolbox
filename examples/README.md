# Examples

This directory contains example configurations and deployment scenarios for the Ultimate K8s Toolbox Helm chart.

## Files

### values-online.yaml
Example values file for deploying the toolbox in an internet-connected environment.

```bash
helm install my-toolbox ../chart -f values-online.yaml -n toolbox --create-namespace
```

### values-offline.yaml
Template values file for deploying in air-gapped/offline environments with an internal container registry.

```bash
# Edit values-offline.yaml with your registry details first
helm install my-toolbox ../chart -f values-offline.yaml -n toolbox --create-namespace
```

### values-mongodb.yaml
Example showing how to deploy the toolbox in a specific namespace (mongodb) using an existing service account.

```bash
helm install my-toolbox ../chart -f values-mongodb.yaml -n mongodb
```

### values-with-ca.yaml
Example demonstrating custom CA certificate trust configuration for enterprise environments with internal PKI.

```bash
# First, create the CA secret
kubectl create secret generic toolbox-ca-certs \
  --from-file=root-ca.crt=/path/to/root-ca.crt \
  --from-file=subordinate-ca.crt=/path/to/sub-ca.crt \
  -n toolbox --create-namespace

# Deploy with CA configuration
helm install my-toolbox ../chart -f values-with-ca.yaml -n toolbox
```

### DEPLOYMENT-EXAMPLES.sh
Executable script containing 10 different deployment scenarios with step-by-step examples.

```bash
# View the examples
cat DEPLOYMENT-EXAMPLES.sh

# Or run specific examples (edit script first)
./DEPLOYMENT-EXAMPLES.sh
```

## Usage Pattern

1. **Start with online deployment** to test basic functionality
2. **Customize values** based on your environment requirements
3. **Use offline template** when deploying to air-gapped environments
4. **Reference examples** for advanced configurations

## Creating Your Own

Copy one of the example files and customize it:

```bash
cp values-online.yaml ../my-custom-values.yaml
# Edit my-custom-values.yaml
helm install my-toolbox ../chart -f my-custom-values.yaml
```

## Workspace Storage

By default, `/workspace` is an ephemeral `emptyDir`. To persist it, set a StorageClass and size to create a PVC:

```bash
helm install my-toolbox ../chart \
  --set workspace.storageClass=<your-storage-class> \
  --set workspace.size=20Gi \
  -n toolbox --create-namespace
```

## See Also

- [QUICKSTART.md](../QUICKSTART.md) - Quick deployment guide
- [README.md](../README.md) - Main documentation
- [OFFLINE-DEPLOYMENT.md](../OFFLINE-DEPLOYMENT.md) - Offline deployment guide

#!/bin/bash
# CA Certificate Import Script for K8s Ultimate Toolbox

cat <<'EOF'
This helper was deprecated during the rename to k8s-ultimate-toolbox.

Use the maintained CA flow in chart/values.yaml or OFFLINE-DEPLOYMENT.md:

  customCA:
    enabled: true
    secretName: toolbox-ca-certs

Then access the deployment with:

  kubectl exec -it -n toolbox deploy/toolbox-k8s-ultimate-toolbox -- bash
EOF

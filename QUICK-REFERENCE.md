# 🚀 Ultimate K8s Admin Workstation - Quick Reference

**One-page cheat sheet for the most common operations**

---

## 📦 Building (nerdctl)

```bash
# Build image
make build-image

# Test image
make test-image

# Create offline bundle
make offline-bundle

# Clean up
make clean
```

---

## ☸️ Deploying (Helm)

```bash
# Install
helm install toolbox chart/ -n toolbox --create-namespace

# Install with Keycloak CLI sidecar
helm install toolbox chart/ -n keycloak-system --create-namespace \
	--set keycloakCli.enabled=true

# Upgrade
helm upgrade toolbox chart/ -n toolbox

# Uninstall
helm uninstall toolbox -n toolbox

# Access pod
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash

# Access Keycloak CLI sidecar
kubectl exec -n keycloak-system -it deploy/toolbox-ultimate-k8s-toolbox -c keycloak-cli -- /bin/sh
```

---

## 🔧 Inside Pod - Essential Commands

### Show All Tools
```bash
show-versions.sh
```

### MongoDB Operations
```bash
# Connect with TLS
mongosh "mongodb://host:27017" --tls --tlsCAFile /tls/ca.crt

# Backup database
mongodump --uri="mongodb://host:27017" --db=mydb --out=/workspace/backup/

# Restore database
mongorestore --uri="mongodb://host:27017" /workspace/backup/mydb/

# Real-time stats
mongostat --uri="mongodb://host:27017" --rowcount=10
```

### TLS Debugging
```bash
# Test TLS connection
openssl s_client -connect host:27017 -tls1_2 -CAfile /tls/ca.crt

# View certificate
openssl x509 -in /tls/server.crt -text -noout

# Verify certificate chain
openssl verify -CAfile /tls/ca.crt /tls/server.crt
```

### DNS & Networking
```bash
# DNS lookup
dig +short service.namespace.svc.cluster.local

# Test connectivity
nc -zv service.namespace.svc.cluster.local 27017
ping -c 3 service.namespace.svc.cluster.local

# Trace route
traceroute service.namespace.svc.cluster.local

# Capture packets (requires privileges)
tcpdump -i any port 27017 -w /workspace/capture.pcap
```

### Kubernetes Operations
```bash
# View all pods
kubectl get pods -A

# Describe pod
kubectl describe pod podname -n namespace

# View logs
kubectl logs -f podname -n namespace

# Get secrets
kubectl get secret secretname -n namespace -o yaml

# Decode secret
kubectl get secret secretname -n namespace -o jsonpath='{.data.key}' | base64 -d
```

### Keycloak Operations
```bash
# Authenticate admin CLI session
kcadm.sh config credentials \
	--server https://keycloak.example.com \
	--realm master \
	--user admin

# List realms
kcadm.sh get realms

# List clients in a realm
kcadm.sh get clients -r myrealm

# Register client using client registration CLI
kcreg.sh config credentials --server https://keycloak.example.com --realm myrealm --user admin
kcreg.sh get my-client-id
```

### Storage Operations
```bash
# Trident info
tridentctl version
tridentctl get backend
tridentctl get volume

# File sync
rsync -avz /source/ /destination/

# Git operations
git clone https://github.com/repo/project.git
git status
```

### Python Scripting
```bash
# Quick MongoDB check
python3 << 'EOF'
from pymongo import MongoClient
client = MongoClient('mongodb://localhost:27017/')
print(client.list_database_names())
EOF

# Kubernetes operations
python3 << 'EOF'
from kubernetes import client, config
config.load_incluster_config()
v1 = client.CoreV1Api()
print([pod.metadata.name for pod in v1.list_namespaced_pod("default").items])
EOF
```

---

## 📊 Tool Categories

| Category | Tools |
|----------|-------|
| **MongoDB** | mongosh, mongodump, mongorestore, bsondump, mongostat, mongotop, mongoexport, mongoimport |
| **Keycloak** | kcadm.sh, kcreg.sh, kc.sh |
| **TLS/X.509** | openssl, certtool (gnutls-bin) |
| **Kubernetes** | kubectl, helm, jq, yq, envsubst |
| **Networking** | dig, nslookup, ping, traceroute, netcat, tcpdump, nmap, curl, wget, iperf3 |
| **Storage** | tridentctl, nfs-common, rsync, git, zip/unzip, tar, gzip |
| **Python** | Python 3.12 + pymongo, kubernetes, pyyaml, requests, jinja2, click |
| **System** | vim, nano, htop, less, strace, lsof, iotop, bash-completion |

---

## 🔍 Common Scenarios

### Scenario 1: Debug MongoDB TLS Connection
```bash
# 1. Check DNS
dig +short mongodb.svc.cluster.local

# 2. Test TCP
nc -zv mongodb.svc.cluster.local 27017

# 3. Verify cert
openssl s_client -connect mongodb.svc.cluster.local:27017 -tls1_2 -CAfile /tls/ca.crt

# 4. Connect
mongosh "mongodb://mongodb.svc.cluster.local:27017" --tls --tlsCAFile /tls/ca.crt
```

### Scenario 2: Troubleshoot Pod
```bash
# 1. Find pod
kubectl get pods -A | grep failing-pod

# 2. Describe
kubectl describe pod failing-pod -n namespace

# 3. View logs
kubectl logs failing-pod -n namespace --previous

# 4. Check events
kubectl get events -n namespace --sort-by='.lastTimestamp'
```

### Scenario 3: Network Performance
```bash
# 1. DNS performance
time dig google.com

# 2. Latency
ping -c 10 service.svc.cluster.local

# 3. Bandwidth (requires iperf3 server)
iperf3 -c iperf-server.local
```

---

## 📚 Documentation

- **[README.md](README.md)** - Complete feature overview
- **[NERDCTL-GUIDE.md](NERDCTL-GUIDE.md)** - nerdctl setup guide
- **[TOOLS-REFERENCE.md](TOOLS-REFERENCE.md)** - Detailed tool reference with examples
- **[INDEX.md](INDEX.md)** - Project navigation

---

## 🆘 Getting Help

```bash
# View installed tools
show-versions.sh

# Check tool version
mongosh --version
kubectl version --client
python3 --version

# Tool help
mongosh --help
kubectl --help
openssl --help
```

---

**Built with nerdctl + containerd for native Kubernetes integration** 🚀

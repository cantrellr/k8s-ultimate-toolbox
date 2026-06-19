# 🚀 Ultimate K8s Admin Workstation - Complete Tools Reference

**Swiss-army knife for Kubernetes, MongoDB, Ops Manager, networking, storage, and cluster inspection**

This document catalogs every tool installed in the toolbox image and provides quick reference examples.

---

## 📦 Section 1: MongoDB Client Stack

### Tools Included

| Tool | Version | Purpose |
|------|---------|---------|
| `mongosh` | 2.3.7 | Modern MongoDB Shell |
| `mongodump` | 100.13.0 | Database backup utility |
| `mongorestore` | 100.13.0 | Database restore utility |
| `bsondump` | 100.13.0 | BSON file inspector |
| `mongostat` | 100.13.0 | Real-time MongoDB stats |
| `mongotop` | 100.13.0 | Track MongoDB read/write activity |
| `mongofiles` | 100.13.0 | GridFS file management |
| `mongoexport` | 100.13.0 | Export data to JSON/CSV |
| `mongoimport` | 100.13.0 | Import data from JSON/CSV |

### Quick Examples

```bash
# Connect to MongoDB with TLS
mongosh "mongodb://rocketchat-db.mongodb.svc.cluster.local:27017" \
  --tls \
  --tlsCAFile /tls/ca.crt \
  --tlsCertificateKeyFile /tls/client.pem

# Verify X.509 authentication
mongosh "mongodb://rocketchat-db.mongodb.svc.cluster.local:27017/?authMechanism=MONGODB-X509" \
  --tls \
  --tlsCAFile /tls/ca.crt \
  --tlsCertificateKeyFile /tls/client.pem

# Backup database
mongodump --uri="mongodb://localhost:27017" \
  --db=rocketchat \
  --out=/workspace/backups/

# Restore database
mongorestore --uri="mongodb://localhost:27017" \
  --db=rocketchat \
  /workspace/backups/rocketchat/

# Export collection to JSON
mongoexport --uri="mongodb://localhost:27017" \
  --db=rocketchat \
  --collection=users \
  --out=/workspace/users.json

# Real-time stats
mongostat --uri="mongodb://localhost:27017" --rowcount=5
```

---

## 🔒 Section 2: X.509 / TLS / Certificate Tools

### Tools Included

- `openssl` - Industry standard SSL/TLS toolkit
- `certtool` (gnutls-bin) - Alternative TLS debugging
- `ca-certificates` - System CA trust management

### Quick Examples

```bash
# Verify server certificate
openssl s_client -connect rocketchat-db.mongodb.svc.cluster.local:27017 \
  -tls1_2 \
  -servername rocketchat-db.mongodb.svc.cluster.local \
  -CAfile /tls/ca.crt

# Show certificate details
openssl x509 -in /tls/server.crt -text -noout

# Verify certificate chain
openssl verify -CAfile /tls/ca.crt /tls/server.crt

# Check certificate expiration
openssl x509 -in /tls/server.crt -noout -enddate

# Test TLS handshake
openssl s_client -connect service.namespace.svc:443 < /dev/null

# Generate CSR (Certificate Signing Request)
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /workspace/client.key \
  -out /workspace/client.csr \
  -subj "/CN=client/O=MyOrg"

# View CSR details
openssl req -in /workspace/client.csr -text -noout

# Check private key matches certificate
openssl x509 -in /tls/server.crt -noout -modulus | md5sum
openssl rsa -in /tls/server.key -noout -modulus | md5sum
```

---

## ☸️ Section 3: Kubernetes Admin Tooling

### Tools Included

| Tool | Version | Purpose |
|------|---------|---------|
| `kubectl` | v1.31.4 | Kubernetes CLI |
| `helm` | Latest v3 | Kubernetes package manager |
| `jq` | Latest | JSON processor |
| `yq` | v4.45.1 | YAML processor |
| `envsubst` | Latest | Environment variable substitution |

### Quick Examples

```bash
# Cluster inspection
kubectl get nodes
kubectl get pods -A
kubectl get svc -A

# Check MongoDB pods
kubectl get pods -n mongodb -o wide
kubectl describe pod mongodb-0 -n mongodb

# View logs
kubectl logs -n mongodb mongodb-0 --tail=100 -f

# Port forward for local access
kubectl port-forward -n mongodb svc/mongodb 27017:27017

# Execute commands in pods
kubectl exec -it -n mongodb mongodb-0 -- mongosh

# Get secrets (base64 encoded)
kubectl get secret -n mongodb mongodb-tls -o yaml

# Decode secret
kubectl get secret -n mongodb mongodb-tls -o jsonpath='{.data.ca\.crt}' | base64 -d

# Helm operations
helm list -A
helm get values -n mongodb mongodb-release
helm upgrade mongodb-release . -n mongodb -f values.yaml

# Process YAML with yq
yq eval '.spec.template.spec.containers[0].image' deployment.yaml
yq eval '.metadata.name' *.yaml

# Parse JSON with jq
kubectl get pod -n mongodb -o json | jq '.items[].metadata.name'
kubectl get nodes -o json | jq '.items[].status.addresses'

# Template substitution
export NAMESPACE=mongodb
export REPLICAS=3
envsubst < deployment.template.yaml > deployment.yaml
```

---

## 🛡️ Section 4: Keycloak CLI Tools

By default, these tools are included when you build the toolbox image from this repository.
If you deploy from a pre-built image, enable the Keycloak CLI sidecar with:

```bash
helm upgrade --install toolbox chart/ -n keycloak-system --create-namespace \
  --set keycloakCli.enabled=true
```

### Tools Included

| Tool | Version | Purpose |
|------|---------|---------|
| `kcadm.sh` | 26.1.4 | Keycloak admin CLI for realm/user/client management |
| `kcreg.sh` | 26.1.4 | Keycloak client registration CLI |
| `kc.sh` | 26.1.4 | Keycloak server distribution CLI |

### Quick Examples

```bash
# Authenticate against Keycloak (admin user)
kcadm.sh config credentials \
  --server https://keycloak.example.com \
  --realm master \
  --user admin

# List realms
kcadm.sh get realms

# List users in a realm
kcadm.sh get users -r myrealm

# Create a realm (idempotent pattern)
kcadm.sh create realms -s realm=myrealm -s enabled=true || true

# Create a client using registration CLI
kcreg.sh config credentials \
  --server https://keycloak.example.com \
  --realm myrealm \
  --user admin
kcreg.sh create -s clientId=my-app -s publicClient=true

# Show server CLI help (for Keycloak image/server operations)
kc.sh --help
```

---

## 🌐 Section 5: Networking Tools

### Tools Included

| Tool | Purpose |
|------|---------|
| `dig` | DNS lookup with detailed output |
| `nslookup` | Simple DNS queries |
| `ping` | ICMP connectivity test |
| `traceroute` | Network path tracing |
| `netcat` (nc) | TCP/UDP connection testing |
| `tcpdump` | Packet capture and analysis |
| `nmap` | Network port scanning |
| `curl` | HTTP client |
| `wget` | File downloader |
| `ip` | Modern network configuration |
| `netstat` | Network statistics (legacy) |
| `telnet` | Raw TCP connection testing |
| `iperf3` | Network bandwidth testing |

### Quick Examples

```bash
# DNS debugging
dig rocketchat-db.mongodb.svc.cluster.local
dig +short rocketchat-db.mongodb.svc.cluster.local
nslookup rocketchat-db.mongodb.svc.cluster.local

# Test service connectivity
ping -c 3 mongodb.mongodb.svc.cluster.local
nc -zv rocketchat-db.mongodb.svc.cluster.local 27017
telnet rocketchat-db.mongodb.svc.cluster.local 27017

# HTTP/HTTPS testing
curl -v https://api.example.com/health
curl -k https://service.namespace.svc:8443/  # Skip TLS verification
wget --no-check-certificate https://service.namespace.svc:8443/file.tar.gz

# Network interface info
ip addr show
ip route show

# Port scanning
nmap -p 27017 rocketchat-db.mongodb.svc.cluster.local
nmap -sT -p 1-65535 192.168.1.10  # Full TCP port scan

# Packet capture (requires elevated privileges)
tcpdump -i any port 27017 -w /workspace/mongodb-traffic.pcap
tcpdump -i eth0 -n host 10.0.0.5

# Trace network path
traceroute google.com
traceroute -T -p 443 api.example.com  # TCP traceroute

# Bandwidth testing (requires iperf3 server)
iperf3 -c iperf-server.namespace.svc -t 30  # 30 second test

# Check listening ports
netstat -tuln
ss -tuln  # Modern alternative
```

---

## 💾 Section 6: Storage + File Transfer Tools

### Tools Included

| Tool | Purpose |
|------|---------|
| `tridentctl` | NetApp Trident storage management |
| `nfs-common` | NFS client utilities |
| `rsync` | Advanced file synchronization |
| `git` | Version control |
| `zip/unzip` | ZIP archive handling |
| `tar` | TAR archive handling |
| `gzip` | GZIP compression |

### Quick Examples

```bash
# Trident storage inspection
tridentctl version
tridentctl get backend
tridentctl get storageclass
tridentctl get volume

# NFS mounting (requires root/capabilities)
mount -t nfs nfs-server.local:/export /mnt/nfs

# Rsync file transfer
rsync -avz --progress /workspace/backups/ /mnt/backups/
rsync -e ssh /workspace/data.tar.gz user@remote:/backups/

# Git operations
git clone https://github.com/org/repo.git
git status
git log --oneline -10

# Archive operations
tar -czf backup-$(date +%Y%m%d).tar.gz /workspace/data/
tar -xzf backup.tar.gz -C /workspace/restore/

# Compression
gzip large-file.sql
gunzip large-file.sql.gz

# ZIP operations
zip -r backup.zip /workspace/configs/
unzip -l backup.zip  # List contents
unzip backup.zip -d /workspace/extract/
```

---

## 🐍 Section 7: Python Environment

### Packages Installed

| Package | Purpose |
|---------|---------|
| `pymongo` | MongoDB driver |
| `kubernetes` | Kubernetes Python client |
| `pyyaml` | YAML processing |
| `requests` | HTTP client library |
| `jinja2` | Template engine |
| `click` | CLI framework |

### Quick Examples

```bash
# Python MongoDB operations
python3 << 'EOF'
from pymongo import MongoClient
client = MongoClient('mongodb://localhost:27017/')
db = client['rocketchat']
print(db.list_collection_names())
EOF

# Kubernetes operations
python3 << 'EOF'
from kubernetes import client, config
config.load_incluster_config()
v1 = client.CoreV1Api()
print([pod.metadata.name for pod in v1.list_namespaced_pod("mongodb").items])
EOF

# YAML processing
python3 << 'EOF'
import yaml
with open('values.yaml') as f:
    data = yaml.safe_load(f)
print(data['image']['tag'])
EOF

# HTTP requests
python3 << 'EOF'
import requests
response = requests.get('https://api.github.com/repos/kubernetes/kubernetes')
print(response.json()['stargazers_count'])
EOF

# Template rendering
python3 << 'EOF'
from jinja2 import Template
template = Template("Hello {{ name }}!")
print(template.render(name="Kubernetes"))
EOF
```

---

## 🛠️ Section 8: System Debugging Tools

### Tools Included

| Tool | Purpose |
|------|---------|
| `vim` / `nano` | Text editors |
| `htop` | Interactive process viewer |
| `less` | File pager |
| `psmisc` | Process utilities (killall, pstree) |
| `strace` | System call tracer |
| `procps` | Process monitoring (ps, top) |
| `lsof` | List open files |
| `iotop` | I/O monitoring |
| `file` | File type detection |
| `bash-completion` | Tab completion |

### Quick Examples

```bash
# Process monitoring
htop  # Interactive viewer
top -bn1 | head -20  # Quick snapshot
ps aux | grep mongod
pstree -p  # Process tree

# File operations
vim /workspace/config.yaml
nano /workspace/notes.txt
less /var/log/application.log

# Process management
killall mongod  # Kill all mongod processes
pgrep -a mongosh  # Find processes by name

# System call tracing
strace -c kubectl get pods  # Count syscalls
strace -e trace=open,read kubectl get pods  # Trace specific calls

# Open files inspection
lsof -i :27017  # What's using port 27017?
lsof -u toolbox  # Files opened by user
lsof /workspace  # Processes using workspace

# I/O monitoring
iotop -n 5  # 5 iterations
iostat -x 1 5  # Extended stats

# File type detection
file /workspace/backup.tar.gz
file -i /workspace/data.json  # MIME type
```

---

## 🔐 Section 9: CA Trust Integration

### Features

- Automatic CA certificate trust when mounted at `/tls/ca.crt`
- Script available: `/usr/local/bin/update-ca-trust.sh`
- All TLS tools (curl, wget, mongosh) will trust the custom CA

### Usage

```bash
# Manual CA trust update (if needed)
sudo /usr/local/bin/update-ca-trust.sh

# Verify trusted CAs
ls /usr/local/share/ca-certificates/custom/

# Test with curl
curl https://internal-service.local/

# Test with mongosh (will use system CA trust)
mongosh "mongodb+srv://cluster.internal.local/mydb"
```

### Kubernetes Deployment with CA

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: toolbox
spec:
  containers:
  - name: toolbox
    image: ultimate-k8s-toolbox:v1.0.2
    volumeMounts:
    - name: tls
      mountPath: /tls
      readOnly: true
    command: ["/bin/bash", "-c"]
    args:
    - |
      /usr/local/bin/update-ca-trust.sh
      exec tail -f /dev/null
  volumes:
  - name: tls
    secret:
      secretName: cluster-ca
      items:
      - key: ca.crt
        path: ca.crt
```

---

## 🎯 Common Operational Scenarios

### Scenario 1: Debug MongoDB TLS Connection

```bash
# 1. Check DNS resolution
dig +short rocketchat-db.mongodb.svc.cluster.local

# 2. Test TCP connectivity
nc -zv rocketchat-db.mongodb.svc.cluster.local 27017

# 3. Verify certificate
openssl s_client -connect rocketchat-db.mongodb.svc.cluster.local:27017 \
  -tls1_2 -servername rocketchat-db.mongodb.svc.cluster.local \
  -CAfile /tls/ca.crt

# 4. Connect with mongosh
mongosh "mongodb://rocketchat-db.mongodb.svc.cluster.local:27017" \
  --tls --tlsCAFile /tls/ca.crt
```

### Scenario 2: Kubernetes Pod Troubleshooting

```bash
# 1. Find the pod
kubectl get pods -A | grep failing-pod

# 2. Check pod details
kubectl describe pod failing-pod -n namespace

# 3. View logs
kubectl logs failing-pod -n namespace --previous

# 4. Check events
kubectl get events -n namespace --sort-by='.lastTimestamp'

# 5. Execute debug commands in pod
kubectl exec -it failing-pod -n namespace -- bash
```

### Scenario 3: Network Performance Testing

```bash
# 1. Test DNS performance
time dig google.com +short

# 2. Test latency
ping -c 10 service.namespace.svc.cluster.local

# 3. Test bandwidth
iperf3 -c iperf-server.local

# 4. Capture traffic
tcpdump -i any port 27017 -w traffic.pcap
```

### Scenario 4: Storage Investigation

```bash
# 1. Check Trident backends
tridentctl get backend

# 2. List volumes
tridentctl get volume

# 3. Check NFS mounts
df -h | grep nfs

# 4. Test storage performance
dd if=/dev/zero of=/workspace/test.img bs=1M count=1000
```

---

## 📚 Additional Resources

- [MongoDB Documentation](https://docs.mongodb.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [OpenSSL Cookbook](https://www.feistyduck.com/library/openssl-cookbook/)
- [Network Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/debug-application/)

---

## 🆘 Getting Help

Run the built-in version checker:

```bash
show-versions.sh
```

This displays all installed tools and their versions.

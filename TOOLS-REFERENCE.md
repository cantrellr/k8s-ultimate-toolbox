# Tools Reference - K8s Ultimate Toolbox v1.1.0

This file is the operator-facing inventory for the toolbox image. It lists the pinned tools, their purpose, and the first command to run when troubleshooting.

## Version matrix

| Tool | Version / Source | Purpose |
|---|---:|---|
| `kubectl` | `v1.36.1` | Kubernetes API inspection and object management |
| `helm` | `v4.2.1` | Helm chart lifecycle and release debugging |
| `yq` | `v4.53.3` | YAML, JSON, XML, and TOML processing |
| `jq` | Ubuntu 24.04 | JSON processing |
| Keycloak distribution CLI | `26.6.3` | `kcadm.sh`, `kcreg.sh`, `kc.sh` |
| `mongosh` | `2.8.3` | MongoDB shell |
| MongoDB Database Tools | `100.17.0` | `mongodump`, `mongorestore`, `mongostat`, `mongotop`, `mongoexport`, `mongoimport`, `bsondump` |
| PostgreSQL client stack | Ubuntu 24.04 packages | `psql`, `pg_isready`, `pg_dump`, `pg_restore`, `pgbench` |
| PostgreSQL diagnostics | Ubuntu/PyPI | `pgbadger`, `pgcli`, `pg_activity`, `psycopg` |
| NetApp Trident CLI | `26.02.0` | Trident CSI troubleshooting |
| Python | Ubuntu 24.04 | Automation and ad-hoc diagnostics |
| MySQL client | Ubuntu 24.04 | MySQL/MariaDB client testing |
| Redis CLI | Ubuntu 24.04 | Redis connectivity and command testing |

## Kubernetes and Helm

```bash
kubectl version --client=true
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl describe pod -n <namespace> <pod>
kubectl get events -A --sort-by='.lastTimestamp'
helm list -A
helm get values <release> -n <namespace>
helm get manifest <release> -n <namespace>
```

## Keycloak

Use `keycloak-login.sh` for the safe default flow:

```bash
export KEYCLOAK_URL=https://keycloak.example.com
export KEYCLOAK_USER=admin
export KEYCLOAK_PASSWORD='<secret>'
export KEYCLOAK_REALM=master
keycloak-login.sh
```

Then inspect:

```bash
kcadm.sh get realms
kcadm.sh get clients -r <realm>
kcadm.sh get users -r <realm> --first 0 --max 20
```

## PostgreSQL

```bash
pg_isready -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER"
pg-diagnostics.sh
psql -c 'select version();'
pg_dump --schema-only --file=/workspace/schema.sql
pgbadger /workspace/postgresql.log -o /workspace/postgres-report.html
```

## MongoDB

```bash
mongosh "$MONGODB_URI"
mongostat --uri "$MONGODB_URI" --rowcount 5
mongotop --uri "$MONGODB_URI" 5
mongodump --uri "$MONGODB_URI" --archive=/workspace/mongodb.archive --gzip
```

## Network and TLS

```bash
dig <service>.<namespace>.svc.cluster.local
nslookup kubernetes.default.svc.cluster.local
curl -Iv https://<service>
openssl s_client -connect <host>:443 -servername <host> -showcerts
nc -vz <host> <port>
nmap -Pn -p <port> <host>
tcpdump -i any -nn host <ip>
mtr -rw <host>
iperf3 -c <host>
```

## Storage

```bash
tridentctl version --client
tridentctl get backend -n trident
tridentctl get volume -n trident
mount | grep nfs
showmount -e <nfs-server>
```

## System and scripting

```bash
python3 --version
python3 - <<'PY'
import kubernetes, requests, yaml
print('python diagnostics ready')
PY

strace -f -p <pid>
lsof -i -P -n
htop
```

## Operational helpers

| Helper | Purpose |
|---|---|
| `show-versions.sh` | Prints the installed toolchain summary |
| `pg-diagnostics.sh` | PostgreSQL connectivity, activity, lock, size, and replication triage |
| `keycloak-login.sh` | Authenticates `kcadm.sh` using environment variables |
| `update-ca-trust.sh` | Loads custom CAs into the system trust store when used interactively |

## Image-bloat discipline

Do not add every cool CLI by default. Add tools that meet at least one of these criteria:

1. They diagnose a common outage mode.
2. They support air-gapped operations.
3. They reduce time-to-evidence during incidents.
4. They are broadly useful across clusters and do not hard-couple the image to one vendor.
5. They can be pinned, verified, and documented.

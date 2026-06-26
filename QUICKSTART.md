# Quick Start - K8s Ultimate Toolbox

This guide gets the v1.1.0 toolbox running and validates the Kubernetes, Keycloak, MongoDB, and PostgreSQL tooling.

## 1. Deploy online

```bash
git clone https://github.com/cantrellr/k8s-ultimate-toolbox.git
cd k8s-ultimate-toolbox

helm install toolbox ./chart \
  -n toolbox --create-namespace

kubectl wait --for=condition=available deploy/toolbox-ultimate-k8s-toolbox \
  -n toolbox --timeout=300s

kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
```

Inside the pod:

```bash
show-versions.sh
```

## 2. Deploy with persistent workspace

Use this when you want to keep generated reports, exported manifests, PostgreSQL log reports, or packet captures.

```bash
helm install toolbox ./chart \
  -n toolbox --create-namespace \
  --set workspace.storageClass=<storage-class> \
  --set workspace.size=20Gi
```

## 3. Deploy with internal CA certificates

```bash
kubectl create namespace toolbox --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic toolbox-ca-certs \
  --from-file=root-ca.crt=/path/to/root-ca.crt \
  --from-file=subordinate-ca.crt=/path/to/subordinate-ca.crt \
  -n toolbox

helm install toolbox ./chart \
  -n toolbox \
  --set customCA.enabled=true \
  --set customCA.secretName=toolbox-ca-certs
```

Validate from inside the pod:

```bash
update-ca-trust.sh --list
curl -Iv https://internal-service.example.com
```

## 4. Keycloak usage

The primary toolbox image includes Keycloak CLI tools. Use `keycloak-login.sh` after setting the Keycloak URL, realm, and admin user in the shell. Keep the credential in a Kubernetes Secret, a short-lived shell session, or another approved secret source. Do not paste production credentials into shared terminal history. That is how small mistakes become incident reports.

```bash
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
keycloak-login.sh
kcadm.sh get realms
```

Optional official Keycloak CLI sidecar:

```bash
helm upgrade --install toolbox ./chart \
  -n keycloak-system --create-namespace \
  --set keycloakCli.enabled=true

kubectl exec -n keycloak-system -it deploy/toolbox-ultimate-k8s-toolbox -c keycloak-cli -- /bin/sh
```

## 5. PostgreSQL diagnostics

Set the PostgreSQL host, port, database, and user in your shell. Source the credential from your approved secret workflow instead of typing it into shared shell history.

```bash
kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
pg_isready
pg-diagnostics.sh
```

Useful one-liners:

```bash
psql -c 'select version();'
psql -c "select state, count(*) from pg_stat_activity group by state order by count(*) desc;"
psql -c "select pid, now() - query_start as age, wait_event_type, wait_event, left(query, 200) from pg_stat_activity where state <> 'idle' order by age desc limit 10;"
pg_dump --schema-only --file=/workspace/schema.sql
```

For log analysis:

```bash
pgbadger /workspace/postgresql.log -o /workspace/postgres-report.html
```

## 6. MongoDB diagnostics

```bash
mongosh "$MONGODB_URI"
mongostat --uri "$MONGODB_URI" --rowcount 5
mongotop --uri "$MONGODB_URI" 5
mongodump --uri "$MONGODB_URI" --archive=/workspace/mongodb.archive --gzip
```

## 7. Build and test the image

```bash
make info
make build-image
make test-image
```

## 8. Offline bundle

On an internet-connected build host:

```bash
make offline-bundle
```

Transfer `dist/ultimate-k8s-toolbox-offline-v1.1.0.tar.gz` to the offline environment, extract it, load/push the image to the internal registry, then install the packaged chart.

```bash
tar -xzf ultimate-k8s-toolbox-offline-v1.1.0.tar.gz
cd offline-bundle
cat MANIFEST.txt 2>/dev/null || true
cat SBOM.txt
```

## 9. Common operations

```bash
helm list -n toolbox
kubectl get pods -n toolbox
kubectl logs -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox
kubectl describe pod -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox
kubectl get events -n toolbox --sort-by='.lastTimestamp'
helm get values toolbox -n toolbox
helm upgrade toolbox ./chart --reuse-values -n toolbox
helm uninstall toolbox -n toolbox
```

## 10. Troubleshooting install failures

```bash
helm lint ./chart
helm template toolbox ./chart -n toolbox --debug
kubectl describe deploy toolbox-ultimate-k8s-toolbox -n toolbox
kubectl describe pod -n toolbox -l app.kubernetes.io/name=ultimate-k8s-toolbox
```

Hard truth: most failures here are image pull paths, missing registry credentials, insufficient RBAC, or clusters blocking `NET_ADMIN`/`NET_RAW` through Pod Security Admission. Check those first before chasing ghosts.

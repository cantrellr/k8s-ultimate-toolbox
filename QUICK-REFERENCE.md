# 🚀 K8s Ultimate Toolbox - Quick Reference

**One-page cheat sheet for common operations**

## Building

```bash
make build-image
make test-image
make offline-bundle
```

## Deploying

```bash
helm upgrade --install toolbox chart/ -n toolbox --create-namespace
kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
```

## Inside the pod

```bash
show-versions.sh
```

## Runtime and control plane

```bash
crictl ps -a
crictl images
etcdctl endpoint health --cluster
etcdutl snapshot status /workspace/snapshot.db
```

## Certificates, policy, and CNI

```bash
cmctl check api
step certificate inspect /path/to/cert.crt --short
kubent
kubeconform -summary rendered.yaml
popeye
cilium status
hubble status
calicoctl get ippools
```

## Keycloak

```bash
keycloak-login.sh
kcadm.sh get realms
kcadm.sh get clients -r myrealm
```

## Databases

```bash
pg_isready
pg-diagnostics.sh
mongosh "$MONGODB_URI"
mongostat --uri "$MONGODB_URI" --rowcount 5
```

## Networking

```bash
dig +short service.namespace.svc.cluster.local
nc -zv service.namespace.svc.cluster.local 443
traceroute service.namespace.svc.cluster.local
tcpdump -i any port 443 -w /workspace/capture.pcap
```

## Documentation

- [README.md](README.md)
- [QUICKSTART.md](QUICKSTART.md)
- [TOOLS-REFERENCE.md](TOOLS-REFERENCE.md)
- [docs/INDEX.md](docs/INDEX.md)

**Built with Docker or nerdctl + containerd for Kubernetes diagnostics.**

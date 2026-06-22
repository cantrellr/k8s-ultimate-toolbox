# Keycloak Operations Guide

The toolbox includes Keycloak CLI support in two ways:

1. The primary toolbox image includes `kcadm.sh`, `kcreg.sh`, and `kc.sh` from Keycloak `26.6.3`.
2. The Helm chart can optionally deploy an official Keycloak CLI sidecar using `quay.io/keycloak/keycloak:26.6.3`.

Use the primary image for normal platform operations. Use the sidecar when you want identity tooling isolated from the rest of the diagnostic workstation.

## Deploy with built-in Keycloak tools

```bash
helm upgrade --install toolbox ./chart \
  -n toolbox --create-namespace

kubectl exec -n toolbox -it deploy/toolbox-ultimate-k8s-toolbox -- bash
```

Validate:

```bash
kcadm.sh --help
kcreg.sh --help
kc.sh --help
```

## Deploy with Keycloak sidecar

```bash
helm upgrade --install toolbox ./chart \
  -n keycloak-system --create-namespace \
  --set keycloakCli.enabled=true

kubectl exec -n keycloak-system -it deploy/toolbox-ultimate-k8s-toolbox -c keycloak-cli -- /bin/sh
```

## Authenticate

The helper script uses environment variables and intentionally avoids printing secrets.

```bash
export KEYCLOAK_URL=https://keycloak.example.com
export KEYCLOAK_USER=admin
export KEYCLOAK_PASSWORD='<secret>'
export KEYCLOAK_REALM=master
export KEYCLOAK_CLIENT=admin-cli

keycloak-login.sh
```

Equivalent raw command:

```bash
kcadm.sh config credentials \
  --server "$KEYCLOAK_URL" \
  --realm "${KEYCLOAK_REALM:-master}" \
  --client "${KEYCLOAK_CLIENT:-admin-cli}" \
  --user "$KEYCLOAK_USER" \
  --password "$KEYCLOAK_PASSWORD"
```

## Common inspections

```bash
kcadm.sh get realms
kcadm.sh get realms/<realm>
kcadm.sh get clients -r <realm>
kcadm.sh get users -r <realm> --first 0 --max 20
kcadm.sh get roles -r <realm>
kcadm.sh get groups -r <realm>
kcadm.sh get identity-provider/instances -r <realm>
```

## Client checks

```bash
CLIENT_ID='<client-id>'
REALM='<realm>'

CLIENT_UUID=$(kcadm.sh get clients -r "$REALM" -q clientId="$CLIENT_ID" --fields id --format csv | tail -n +2 | tr -d '"')
kcadm.sh get clients/$CLIENT_UUID -r "$REALM"
kcadm.sh get clients/$CLIENT_UUID/client-secret -r "$REALM"
```

Only retrieve client secrets when you have authorization and a reason. Secrets copied into shell history, tickets, or chat are still secrets leaked. Don’t make the incident worse.

## Realm export

For ad-hoc inspection only:

```bash
kcadm.sh get realms/<realm> > /workspace/<realm>-realm.json
kcadm.sh get clients -r <realm> > /workspace/<realm>-clients.json
kcadm.sh get identity-provider/instances -r <realm> > /workspace/<realm>-idps.json
```

## Troubleshooting login failures

Check the basics first:

```bash
curl -k -I "$KEYCLOAK_URL/realms/master/.well-known/openid-configuration"
openssl s_client -connect keycloak.example.com:443 -servername keycloak.example.com -showcerts </dev/null
```

Common causes:

| Symptom | Likely issue |
|---|---|
| TLS verification failure | Missing internal CA; enable `customCA` or mount CA bundle |
| `401 Unauthorized` | Wrong realm, bad admin credentials, disabled user, bad client |
| `403 Forbidden` | User authenticated but lacks admin permissions |
| DNS failure | Cluster DNS or service name issue |
| Timeout | NetworkPolicy, service mesh policy, ingress route, or firewall |

## Recommended security model

Use a dedicated admin account for toolbox operations. Scope the account to the minimum set of realms and actions required. Prefer temporary credentials or short-lived access workflows. Do not store Keycloak admin secrets in the repo, image, Helm values file, or screenshots.

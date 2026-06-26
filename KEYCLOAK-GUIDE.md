# Keycloak Operations Guide

The default K8s Ultimate Toolbox image includes Keycloak CLI support directly in the primary `toolbox` container:

- `kcadm.sh`
- `kcreg.sh`
- `kc.sh`
- `keycloak-login.sh`

There is no separate Keycloak sidecar. That keeps the deployment simpler, reduces image pull complexity in air-gapped environments, and avoids a second operational shell with a different toolchain.

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
command -v keycloak-login.sh
```

## Authenticate

The helper script uses environment variables and intentionally avoids printing secrets. Source sensitive values from Kubernetes Secrets, your password manager, or a short-lived approved access workflow. Do not put production credentials into Git, Helm values, screenshots, or shared shell history.

```bash
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

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

kubectl exec -n toolbox -it deploy/toolbox-k8s-ultimate-toolbox -- bash
```

Validate:

```bash
kcadm.sh --help
kcreg.sh --help
kc.sh --help
command -v keycloak-login.sh
```

## Authenticate

The helper script expects `KEYCLOAK_URL`, `KEYCLOAK_USER`, `KEYCLOAK_SECRET`, and optionally `KEYCLOAK_REALM` and `KEYCLOAK_CLIENT`. Source sensitive values from Kubernetes Secrets, your password manager, or a short-lived approved access workflow. Do not put production credentials into Git, Helm values, screenshots, or shared shell history.

```bash
keycloak-login.sh
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

## Realm export

For ad-hoc inspection only:

```bash
kcadm.sh get realms/<realm> > /workspace/<realm>-realm.json
kcadm.sh get clients -r <realm> > /workspace/<realm>-clients.json
kcadm.sh get identity-provider/instances -r <realm> > /workspace/<realm>-idps.json
```

## Troubleshooting login failures

Check DNS, TLS, realm name, client name, user status, and admin permissions first. Most failures are not exotic; they are usually stale credentials, a wrong realm, or an internal CA trust issue.

## Recommended security model

Use a dedicated admin account for toolbox operations. Scope the account to the minimum set of realms and actions required. Prefer temporary credentials or short-lived access workflows. Do not store Keycloak admin secrets in the repo, image, Helm values file, or screenshots.

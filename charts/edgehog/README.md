# Edgehog

A Helm chart for deploying [Edgehog](https://edgehog.io), the Open Source Device
Manager by SECO Mind, on Kubernetes.

## Components

The chart deploys three components:

| Component | Image | Description |
|---|---|---|
| Backend | `edgehogdevicemanager/edgehog-backend` | Elixir/Phoenix API server |
| Frontend | `edgehogdevicemanager/edgehog-frontend` | nginx-served web dashboard |
| Device Forwarder | `edgehogdevicemanager/edgehog-device-forwarder` | WebSocket relay for device sessions (optional) |

Ingress, TLS and PostgreSQL are **not** managed by this chart.

## Prerequisites

- Kubernetes >= 1.23, Helm >= 3.8
- An external **PostgreSQL** database reachable from the cluster
- An external **Astarte** instance with an existing realm and its private key
- An **S3-compatible** storage bucket (or Azure Blob container) for OTA updates
- DNS + TLS for three hosts: frontend, backend, and device forwarder

## Installation

```sh
# Generate an Admin API keypair
openssl ecparam -name prime256v1 -genkey -noout > admin_private.pem
openssl ec -in admin_private.pem -pubout > admin_public.pem

# Create required secrets
kubectl create secret generic edgehog-admin-api \
  --from-file=admin_public.pem=./admin_public.pem

kubectl create secret generic edgehog-s3-credentials \
  --from-literal=access-key-id=YOUR_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_SECRET_KEY

kubectl create secret generic edgehog-postgresql \
  --from-literal=password=YOUR_DB_PASSWORD
```

```yaml
# values.yaml
frontend:
  host: edgehog.example.com

backend:
  host: api.edgehog.example.com
  database:
    hostname: postgres.example.com
    passwordExistingSecret: edgehog-postgresql
  storage:
    s3:
      host: s3.amazonaws.com
      bucket: my-bucket
      region: eu-west-1
      assetHost: my-bucket.s3.amazonaws.com
      existingSecret: edgehog-s3-credentials
  adminApi:
    existingSecret: edgehog-admin-api

forwarder:
  host: forwarder.example.com
```

```sh
helm install edgehog oci://ghcr.io/edgehog-device-manager/helm/edgehog -f values.yaml
```

## Database

The backend needs an external PostgreSQL instance. Configure it under
`backend.database`; the password is always referenced from an existing Secret:

```yaml
backend:
  database:
    hostname: postgres.example.com
    username: edgehog
    database: edgehog
    poolSize: 10
    passwordExistingSecret: edgehog-postgresql
    passwordExistingSecretKey: password
```

## Disabling the Device Forwarder

```yaml
forwarder:
  enabled: false
```

## Post-install: provisioning a tenant

Each Edgehog tenant maps 1:1 to an Astarte realm.

1. Generate an admin JWT with
   [`tools/gen-edgehog-jwt`](https://github.com/edgehog-device-manager/edgehog/tree/main/tools),
   signed with your admin private key.
2. Create the tenant via the Admin API:

```sh
curl -X POST "https://api.edgehog.example.com/admin-api/v1/tenants" \
  -H 'Content-Type: application/vnd.api+json' \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"data":{"type":"tenant","attributes":{
    "name":"My Tenant","slug":"my-tenant",
    "public_key":"<tenant public PEM>",
    "astarte_config":{
      "base_api_url":"https://api.astarte.example.com",
      "realm_name":"myrealm",
      "realm_private_key":"<realm private PEM>"}}}}'
```

3. Generate a tenant token and log in with the tenant slug + token.

See the [official deployment guide](https://docs.edgehog.io/deploying_with_kubernetes.html)
for details.

## External Secrets / GitOps

All secrets can be sourced from existing Kubernetes Secrets instead of values.
This is the recommended approach for GitOps (Argo CD / Flux) with
[External Secrets Operator](https://external-secrets.io):

| Secret | Values key | Expected keys |
|---|---|---|
| Backend secret key base | `backend.existingSecret` | `secret-key-base` |
| Forwarder secret key base | `forwarder.existingSecret` | `secret-key-base` |
| Database password | `backend.database.passwordExistingSecret` | `password` |
| Admin API public key | `backend.adminApi.existingSecret` | `admin_public.pem` |
| S3 credentials | `backend.storage.s3.existingSecret` | `access-key-id`, `secret-access-key` |
| GCS service account | `backend.storage.s3.gcpCredentialsExistingSecret` | `credentials.json` |
| Azure credentials | `backend.storage.azure.existingSecret` | `connection-string` or `account-name`/`account-key` |
| Geolocation API keys | `backend.geolocation.existingSecret` | `ipbase-api-key`, `google-geolocation-api-key`, `google-geocoding-api-key` |

**Argo CD**: when no explicit value or `existingSecret` is given, the chart
generates secret key bases with `randAlphaNum`. This re-renders on every sync
and causes permanent `OutOfSync` drift. Always provide them via External
Secrets when using Argo CD.

## Values

See [values.yaml](values.yaml) for the full list of supported values, including
Azure Blob storage, geolocation providers, resource limits, probes,
nodeSelector/tolerations/affinity, and extra environment variables per component.

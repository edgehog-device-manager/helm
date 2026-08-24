# Edgehog Helm Chart

A Helm chart for deploying [Edgehog](https://edgehog.io), the Open Source Device
Manager Platform by SECO Mind, on Kubernetes.

The chart deploys:

- **Backend** (`edgehogdevicemanager/edgehog-backend`) — Elixir/Phoenix API server
- **Frontend** (`edgehogdevicemanager/edgehog-frontend`) — nginx-served dashboard
- **Device Forwarder** (`edgehogdevicemanager/edgehog-device-forwarder`) — WebSocket relay for device sessions (optional)

Routing (Ingress objects), TLS certificates and the PostgreSQL database are
**not** managed by this chart: they are prerequisites you bring with you.

## Prerequisites

- Kubernetes 1.23+ with Helm 3.8+
- An external **PostgreSQL** database reachable from the cluster
- An external **Astarte** instance with an existing realm and its private key
  (tenants are provisioned post-install; see below)
- An **S3-compatible storage** bucket (or Azure Blob container) for OTA updates and files
- DNS names for three hosts pointing at your routing:
  - frontend host (dashboard)
  - backend host (API)
  - device forwarder host
- TLS certificates for the three hosts (e.g. via cert-manager) and the routing
  itself (Ingress, Gateway, LoadBalancer — whatever fits your cluster)

## Installing

```sh
# Generate an Admin API keypair (the private key stays with you!)
openssl ecparam -name prime256v1 -genkey -noout > admin_private.pem
openssl ec -in admin_private.pem -pubout > admin_public.pem

helm install edgehog charts/edgehog \
  --set frontend.host=edgehog.example.com \
  --set backend.host=api.edgehog.example.com \
  --set forwarder.host=forwarder.edgehog.example.com \
  --set backend.database.hostname=postgres.example.com \
  --set backend.database.passwordExistingSecret=edgehog-postgresql \
  --set backend.storage.s3.host=s3.amazonaws.com \
  --set backend.storage.s3.bucket=my-bucket \
  --set backend.storage.s3.region=eu-west-1 \
  --set backend.storage.s3.assetHost=my-bucket.s3.amazonaws.com \
  --set backend.storage.s3.accessKeyId=... \
  --set backend.storage.s3.secretAccessKey=... \
  --set backend.adminApi.publicKeyPem="$(cat admin_public.pem)"
```

Secret key bases are generated automatically on first install and persisted in
the release secret across upgrades.

### Database

The backend requires an external PostgreSQL database. Connection settings live
under `backend.database`; the password is always referenced from an existing
Secret and never set in values:

```yaml
backend:
  database:
    hostname: postgres.example.com
    username: edgehog          # default
    database: edgehog          # default
    poolSize: 10               # default
    passwordExistingSecret: edgehog-postgresql
    passwordExistingSecretKey: password   # default
```

Non-standard TLS setups for the database connection can be wired through
`backend.extraEnv` (e.g. `DATABASE_ENABLE_SSL`, `DATABASE_USE_OS_CERTS`).

### Disabling the Device Forwarder

```yaml
forwarder:
  enabled: false
```

## Post-install: provisioning a tenant

Each Edgehog tenant maps 1:1 to an Astarte realm.

1. Generate an admin token with [`tools/gen-edgehog-jwt`](https://github.com/edgehog-device-manager/edgehog/tree/main/tools)
   from the Edgehog repository, signed with your admin **private** key.
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

3. Generate a tenant token and log into the dashboard with the tenant slug + token.

See the [official deployment guide](https://docs.edgehog.io/deploying_with_kubernetes.html)
for details.

## GitOps / External Secrets

Every secret consumed by the chart can be sourced from an existing Kubernetes
Secret instead of values, which is the recommended setup under GitOps
(Argo CD / Flux) together with the [External Secrets Operator](https://external-secrets.io):

| Secret | Values knob | Expected keys |
|---|---|---|
| Phoenix key base (backend) | `backend.existingSecret` | `secret-key-base` |
| Phoenix key base (forwarder) | `forwarder.existingSecret` | `secret-key-base` |
| Database password | `backend.database.passwordExistingSecret` | `password` |
| Admin API public key | `backend.adminApi.existingSecret` | `admin_public.pem` |
| S3 credentials | `backend.storage.s3.existingSecret` | access-key-id, secret-access-key |
| GCS service account JSON | `backend.storage.s3.gcpCredentialsExistingSecret` | credentials.json |
| Azure credentials | `backend.storage.azure.existingSecret` | connection-string or account-name/account-key |
| Geolocation API keys | `backend.geolocation.existingSecret` | ipbase-api-key, google-geolocation-api-key, google-geocoding-api-key |

Example modeled on a GCP Secret Manager-backed ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: edgehog-secret-key-base
spec:
  refreshInterval: 2m0s
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcpsm-ss
  target:
    name: edgehog-secret-key-base
  data:
    - secretKey: secret-key-base
      remoteRef:
        key: edgehog-secret-key-base
```

```yaml
backend:
  existingSecret: edgehog-secret-key-base
```

### Argo CD caveats

- **Avoid generated secrets.** When no explicit value or `existingSecret` is
  given, the chart generates secret key bases with `randAlphaNum`, which
  re-renders to a new value on every sync and causes permanent `OutOfSync`
  drift. Under Argo CD always provide them via External Secrets.

## Upgrading

- Generated secrets (secret key bases) are reused across upgrades via lookup.

## Values

See [values.yaml](charts/edgehog/values.yaml) for the full list of supported values, including
Azure Blob storage, geolocation providers, resource limits, probes,
nodeSelector/tolerations/affinity, and extra environment variables per component.

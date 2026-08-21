# Edgehog Helm Chart

A Helm chart for deploying [Edgehog](https://edgehog.io), the Open Source Device
Manager Platform by SECO Mind, on Kubernetes.

The chart deploys:

- **Backend** (`edgehogdevicemanager/edgehog-backend`) — Elixir/Phoenix API server
- **Frontend** (`edgehogdevicemanager/edgehog-frontend`) — nginx-served dashboard
- **Device Forwarder** (`edgehogdevicemanager/edgehog-device-forwarder`) — WebSocket relay for device sessions (optional)
- **PostgreSQL** (bitnami subchart, optional) — database for the backend
- **OpenFGA** (subchart, optional) + a pre-install Job that creates the authorization store/model

## Prerequisites

- Kubernetes 1.23+ with Helm 3.8+
- An ingress controller (defaults assume `nginx`)
- DNS names for three hosts pointing at the cluster:
  - frontend host (dashboard)
  - backend host (API)
  - device forwarder host
- An external **Astarte** instance with an existing realm and its private key
  (tenants are provisioned post-install; see below)
- An **S3-compatible storage** bucket (or Azure Blob container) for OTA updates and files
- TLS certificates for the three hosts (e.g. via cert-manager)

## Installing

```sh
# Generate an Admin API keypair (the private key stays with you!)
openssl ecparam -name prime256v1 -genkey -noout > admin_private.pem
openssl ec -in admin_private.pem -pubout > admin_public.pem

helm dependency update

helm install edgehog . \
  --set frontend.host=edgehog.example.com \
  --set backend.host=api.edgehog.example.com \
  --set forwarder.host=forwarder.edgehog.example.com \
  --set storage.s3.host=s3.amazonaws.com \
  --set storage.s3.bucket=my-bucket \
  --set storage.s3.region=eu-west-1 \
  --set storage.s3.assetHost=my-bucket.s3.amazonaws.com \
  --set storage.s3.accessKeyId=... \
  --set storage.s3.secretAccessKey=... \
  --set backend.adminApi.publicKeyPem="$(cat admin_public.pem)"
```

Secret key bases are generated automatically on first install and persisted in
the release secret across upgrades.

### External PostgreSQL

```yaml
postgresql:
  enabled: false
database:
  hostname: postgres.example.com
  password: ...        # or use existingSecret
```

### Disabling OpenFGA / Device Forwarder

```yaml
authorization:
  provider: none       # skips OpenFGA entirely
openfga:
  enabled: false
forwarder:
  enabled: false
```

When using an existing OpenFGA instance, point the backend at it and provide the
store IDs created from this chart's bundled model (`files/fga`):

```yaml
openfga:
  enabled: false
authorization:
  provider: openfga
  grpcEndpoint: openfga.other-namespace:8081
  storeId: "<id>"
  authModelId: "<id>"
```

### OpenFGA datastore

The bundled OpenFGA defaults to an in-memory datastore (fine for testing). For
production, persist its data, e.g. reusing the bundled PostgreSQL:

```yaml
openfga:
  datastore:
    engine: postgres
    uri: postgres://edgehog:<password>@<release>-postgresql:5432/openfga
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

## Upgrading

- Generated secrets (secret key bases) are reused across upgrades via lookup.
- The OpenFGA init Job only runs on `helm install` (pre-install hook); the store
  IDs secret persists. Reinstalling the release creates a new store — pass
  `authorization.storeId`/`authModelId` explicitly to reuse an existing one.

## Values

See [values.yaml](values.yaml) for the full list of supported values, including
Azure Blob storage, geolocation providers, DB TLS, resource limits, probes,
nodeSelector/tolerations/affinity, and extra environment variables per component.

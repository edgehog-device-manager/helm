# Edgehog Helm Charts

This repository contains the Helm charts for deploying
[Edgehog](https://edgehog.io), the Open Source Device Manager by SECO Mind,
on Kubernetes.

## Charts

| Chart | Description |
|---|---|
| [edgehog](charts/edgehog/) | Deploys the Edgehog platform (backend, frontend, device forwarder) |

## Installation

The chart is published as an OCI package on Artifact Hub:

**<https://artifacthub.io/packages/helm/edgehog/edgehog>**

```sh
# Create required secrets first
kubectl create secret generic edgehog-admin-api --from-file=admin_public.pem
kubectl create secret generic edgehog-s3-credentials \
  --from-literal=access-key-id=... --from-literal=secret-access-key=...
kubectl create secret generic edgehog-postgresql --from-literal=password=...

# Then install referencing those secrets in values.yaml
helm install edgehog oci://ghcr.io/edgehog-device-manager/helm/edgehog -f values.yaml
```

See the [chart README](charts/edgehog/README.md) for prerequisites,
configuration options, and post-install tenant provisioning.

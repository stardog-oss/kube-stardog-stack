# Stardog Quick Start — Helm Chart Deployment Guide
*Docker Hub Images • kube-stardog-stack • Envoy Gateway*

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installing Cert-Manager](#installing-cert-manager)
3. [Installing Envoy Gateway](#installing-envoy-gateway)
4. [Stardog Images from Docker Hub](#stardog-images-from-docker-hub)
5. [kube-stardog-stack Helm Chart](#kube-stardog-stack-helm-chart)
6. [Create a Storage Class (Optional)](#create-a-storage-class-optional)
7. [Create the Namespace](#create-the-namespace)
8. [Create the Stardog License Secret](#create-the-stardog-license-secret)
9. [Prepare the values.yaml File](#prepare-the-valuesyaml-file)
10. [Install the Stardog Helm Chart](#install-the-stardog-helm-chart)
11. [Retrieve the Public IP and Configure DNS](#retrieve-the-public-ip-and-configure-dns)
12. [Verify TLS Certificates](#verify-tls-certificates)
13. [Create Roles on Stardog for IDP](#create-roles-on-stardog-for-idp)
14. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have the following:

- An existing AKS Kubernetes cluster
- `kubectl` and `helm` installed and configured to interact with your cluster
- Stardog License file (`stardog-license-key.bin`)
- Docker Hub access — images are public, no credentials required

---

## Installing Cert-Manager

Cert-Manager is required for automatic TLS certificate provisioning. Install it before Envoy Gateway and Stardog.

**1. Add the Jetstack Helm repository:**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

**2. Install Cert-Manager:**

```bash
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.2 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

**3. Verify:**

```bash
kubectl get pods --namespace cert-manager
```

All pods must be `Running` before proceeding.

> Refer to the [Cert-Manager documentation](https://cert-manager.io/docs/) for advanced configuration options.

---

## Installing Envoy Gateway

Envoy Gateway replaces traditional Ingress controllers and provides a modern, cloud-agnostic traffic management layer.

**What gets installed:**

- Gateway API CRDs: `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `ReferenceGrant`
- Envoy Gateway CRDs: `EnvoyProxy`, `BackendTrafficPolicy`, `ClientTrafficPolicy`, `SecurityPolicy`
- Envoy Gateway controller in the `envoy-gateway` namespace
- Default `GatewayClass` named `envoy-gateway`

> CRDs are cluster-scoped resources — they are not installed inside a namespace.

### Set Variables

```bash
export EG_VERSION="v1.8.1"
export EG_NAMESPACE="envoy-gateway"
export EG_RELEASE_NAME="eg"
```

### Step 1 — Create the Namespace

```bash
kubectl create namespace "${EG_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl get namespace "${EG_NAMESPACE}"
```

### Step 2 — Install Gateway API and Envoy Gateway CRDs

```bash
helm template "${EG_RELEASE_NAME}-crds" \
  oci://docker.io/envoyproxy/gateway-crds-helm \
  --version "${EG_VERSION}" \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -
```

Verify:

```bash
kubectl get crd | grep 'gateway.networking.k8s.io'
kubectl get crd | grep 'gateway.envoyproxy.io'
```

### Step 3 — Install the Envoy Gateway Controller

```bash
helm upgrade --install "${EG_RELEASE_NAME}" \
  oci://docker.io/envoyproxy/gateway-helm \
  --version "${EG_VERSION}" \
  --namespace "${EG_NAMESPACE}" \
  --create-namespace \
  --skip-crds
```

### Step 4 — Wait for Envoy Gateway to Become Ready

```bash
kubectl wait \
  --namespace "${EG_NAMESPACE}" \
  deployment/envoy-gateway \
  --for=condition=Available \
  --timeout=5m

kubectl get pods -n "${EG_NAMESPACE}"
```

### Step 5 — Create the stardog-envoy-gateway-class GatewayClass

The kube-stardog-stack chart expects a `GatewayClass` named `stardog-envoy-gateway-class`. The Envoy Gateway Helm chart creates `envoy-gateway` automatically, but this second class must be created manually.

> This is a cluster-scoped resource. It only needs to be created once.

```bash
kubectl apply -f - <<EOF
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: edap-internal-lb
  namespace: envoy-gateway
spec:
  logging:
    level:
      default: warn

  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/azure-load-balancer-internal: "true"
        externalTrafficPolicy: Local

---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: stardog-envoy-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: edap-internal-lb
    namespace: envoy-gateway
EOF
```

Verify it is accepted:

```bash
kubectl get gatewayclass stardog-envoy-gateway-class \
  -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}{"\n"}'
```

Expected output: `True`

> Do not proceed until `ACCEPTED` shows `True`. If it stays `False` or `Unknown`, check that the Envoy Gateway controller pod is `Running`.

### Quick Status Check

```bash
kubectl get crd | grep -E 'gateway.networking.k8s.io|gateway.envoyproxy.io'
kubectl get pods -n "${EG_NAMESPACE}"
kubectl get gatewayclass
```

---

## Stardog Images from Docker Hub

All images are publicly available on [Docker Hub](https://hub.docker.com/u/stardog). No credentials required.

| Image | Tag | Description |
|---|---|---|
| `stardog/stardog` | `12.1.0` | Core Stardog graph database |
| `stardog/launchpad` | `v3.10.0` | Web UI (Designer, Explorer, Studio) |
| `stardog/voicebox-service` | `v0.30.0` | Natural language interface |

### Pull from Docker Hub

```bash
docker pull stardog/stardog:12.1.0
docker pull stardog/launchpad:v3.10.0
docker pull stardog/voicebox-service:v0.30.0
```

### Tag and Push to Internal Registry

```bash
export INTERNAL_REGISTRY="<your-internal-registry>"  # e.g. myregistry.azurecr.io

docker tag stardog/stardog:12.1.0           ${INTERNAL_REGISTRY}/stardog:12.1.0
docker tag stardog/launchpad:v3.10.0        ${INTERNAL_REGISTRY}/launchpad:v3.10.0
docker tag stardog/voicebox-service:v0.30.0 ${INTERNAL_REGISTRY}/voicebox-service:v0.30.0

docker login ${INTERNAL_REGISTRY}

docker push ${INTERNAL_REGISTRY}/stardog:12.1.0
docker push ${INTERNAL_REGISTRY}/launchpad:v3.10.0
docker push ${INTERNAL_REGISTRY}/voicebox-service:v0.30.0
```

Verify:

```bash
docker pull ${INTERNAL_REGISTRY}/stardog:12.1.0
docker pull ${INTERNAL_REGISTRY}/launchpad:v3.10.0
docker pull ${INTERNAL_REGISTRY}/voicebox-service:v0.30.0
```

> **Production:** Mirror images into your own internal registry. Stardog does not offer an SLA for retrieving images directly from public repositories.

---

## kube-stardog-stack Helm Chart

The official open-source umbrella chart managing the complete Stardog ecosystem: Stardog, Launchpad, Voicebox, Cache Target, and ZooKeeper.

- **GitHub:** https://github.com/stardog-oss/kube-stardog-stack
- **Public Helm repo:** https://stardog-oss.github.io/kube-stardog-stack
- **Version:** `1.1.2`

**1. Add the repository:**

```bash
helm repo add stardog https://stardog-oss.github.io/kube-stardog-stack
helm repo update
```

**2. Pull the chart for internal mirroring (recommended for production):**

```bash
export VERSION=1.1.2
helm pull stardog/kube-stardog-stack --version ${VERSION}
# Push kube-stardog-stack-${VERSION}.tgz to your internal Helm registry
```

---

## Create a Storage Class (Optional)

Skip this section if your AKS cluster already has a suitable default `StorageClass`. Only create a custom one if you need specific disk settings such as `StandardSSD_LRS`.

Create `stardog-sc.yaml`:

```yaml
allowVolumeExpansion: true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: stardog-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
parameters:
  skuname: StandardSSD_LRS
provisioner: disk.csi.azure.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

Apply and verify:

```bash
kubectl apply -f stardog-sc.yaml
kubectl get storageclass
```

---

## Create the Namespace

```bash
kubectl create namespace stardog-ns
```

---

## Create the Stardog License Secret

**1. Set the license path:**

```bash
export STARDOG_LICENSE=/path/to/stardog-license-key.bin
```

**2. Create the secret:**

```bash
kubectl create secret generic stardog-license \
  --from-file=stardog-license-key.bin=$STARDOG_LICENSE \
  --namespace stardog-ns
```

**3. Verify:**

```bash
kubectl get secret stardog-license --namespace stardog-ns
```

---

## Prepare the values.yaml File

Create a `quickstart_values.yaml` file with the following configuration. Pay special attention to the `certIssuer` and `gateway` sections — incorrect values here are the most common source of deployment failures.

```yaml
global:
  stardog:
    enabled: true
  launchpad:
    enabled: true
  voicebox:
    enabled: true
  gateway:
    enabled: true
    createGateway: true
    # className defaults to stardog-envoy-gateway-class — no override needed
    name: stardog-gateway
    namespace: envoy-gateway      # MUST be the Envoy Gateway controller namespace, not stardog-ns
    domain: your-domain.com       # required — must match your DNS record
  certIssuer:
    enabled: true
    clusterScoped: true           # REQUIRED — gateway is in a different namespace than the release
    type: acme
    acme:
      email: "your-email@your-domain.com"
      server: "https://acme-v02.api.letsencrypt.org/directory"
      # REQUIRED — HTTP-01 challenges must attach to the port-80 Gateway
      # listeners. HTTPS listeners are not ready until the certificates exist.
      solvers:
        - selector:
            dnsNames:
              - "sparql.your-domain.com"
          http01:
            gatewayHTTPRoute:
              parentRefs:
                - name: stardog-gateway
                  namespace: envoy-gateway
                  kind: Gateway
                  sectionName: sparql-http
        - selector:
            dnsNames:
              - "launchpad.your-domain.com"
          http01:
            gatewayHTTPRoute:
              parentRefs:
                - name: stardog-gateway
                  namespace: envoy-gateway
                  kind: Gateway
                  sectionName: launchpad-http

stardog:
  image:
    registry: <your-internal-registry>   # e.g. myregistry.azurecr.io
    repository: stardog/stardog
    tag: "12.1.0"
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "8Gi"
      cpu: "4"

launchpad:
  image:
    registry: <your-internal-registry>
    repository: stardog/launchpad
    tag: "v3.10.0"
  env:
    STARDOG_INTERNAL_ENDPOINT: "http://stardog-stardog:5820"
    FRIENDLY_NAME: "My Stardog Applications"

voicebox:
  image:
    registry: <your-internal-registry>
    repository: stardog/voicebox-service
    tag: "v0.30.0"
```

> **`global.gateway.namespace: envoy-gateway` is required.** The Gateway resource must live in the same namespace as the Envoy Gateway controller. Setting it to `stardog-ns` will result in a Gateway that is never programmed.

> **`certIssuer.clusterScoped: true` is required.** Omitting this causes the Helm install to fail with: `gateway.http.tls.secretNamespace outside the release namespace requires certIssuer.clusterScoped=true`.

> **`solvers.http01.gatewayHTTPRoute` is required.** Without it, cert-manager creates `Ingress` resources that Envoy Gateway cannot process. Let's Encrypt will never complete the HTTP-01 challenge and all TLS certificates will stay `Ready: False` indefinitely.
>
> **Use the HTTP listener section names for ACME.** For the shared Gateway created by this chart, the HTTP-01 solver parent refs must use `sectionName: sparql-http` and `sectionName: launchpad-http`. Do not point ACME solvers at the HTTPS listeners (`sparql` or `launchpad`), because those listeners are not ready until their TLS secrets exist.

### Configure IDP

Configure PingIdentity or EntraID following the provider documentation.

- **Entra-ID:** https://github.com/stardog-union/launchpad-docs/blob/main/providers/microsoft-entra.md

---

## Install the Stardog Helm Chart

**1. Run the Helm install:**

```bash
helm upgrade --install stardog \
  stardog/kube-stardog-stack --version 1.1.2 \
  --namespace stardog-ns \
  --values ./quickstart_values.yaml \
  --timeout 10m0s
```

Or from a local chart artifact:

```bash
helm upgrade --install stardog \
  kube-stardog-stack-1.1.2.tgz \
  --namespace stardog-ns \
  --values ./quickstart_values.yaml \
  --timeout 10m0s
```

**2. Verify all pods are running:**

```bash
kubectl get pods --namespace stardog-ns
```

Expected pods:

```
launchpad-stardog-0        1/1     Running
stardog-0                  1/1     Running
voicebox-stardog-<id>      1/1     Running
```

**3. Verify the Gateway was created:**

```bash
kubectl get gateway -n envoy-gateway
```

The `PROGRAMMED` column must show `True` and an `ADDRESS` must be present before proceeding.

---

## Retrieve the Public IP and Configure DNS

> This step is only possible **after** the Helm install completes and the Gateway is `PROGRAMMED: True`.

**1. Get the public IP:**

```bash
kubectl get gateway stardog-gateway -n envoy-gateway \
  -o jsonpath='{.status.addresses[0].value}{"\n"}'
```

If the Gateway name is unknown, discover it dynamically:

```bash
export GATEWAY_NAME=$(kubectl get gateway -n envoy-gateway \
  -o jsonpath='{.items[0].metadata.name}')
export GATEWAY_IP=$(kubectl get gateway ${GATEWAY_NAME} -n envoy-gateway \
  -o jsonpath='{.status.addresses[0].value}')
echo "Gateway: ${GATEWAY_NAME}  IP: ${GATEWAY_IP}"
```

**2. Create DNS A records:**

In your DNS provider, create an `A` record for each domain pointing to the IP above:

| Record | Type | Value |
|---|---|---|
| `launchpad.your-domain.com` | A | `<GATEWAY_IP>` |
| `sparql.your-domain.com` | A | `<GATEWAY_IP>` |

> The domains must match the value set in `global.gateway.domain` in your `quickstart_values.yaml`. DNS propagation may take a few minutes to several hours depending on your provider's TTL settings.

**3. Re-run the Stardog Helm install after DNS is configured:**

The first Helm install creates the Gateway and assigns the public IP. After the DNS `A` records point to that IP, run the Helm command again so cert-manager can create and validate the ACME HTTP-01 certificate challenges against resolvable hostnames.

```bash
helm upgrade --install stardog \
  stardog/kube-stardog-stack --version 1.1.2 \
  --namespace stardog-ns \
  --values ./quickstart_values.yaml \
  --timeout 10m0s
```

Or from a local chart artifact:

```bash
helm upgrade --install stardog \
  kube-stardog-stack-1.1.2.tgz \
  --namespace stardog-ns \
  --values ./quickstart_values.yaml \
  --timeout 10m0s
```

If certificate challenges were already created before DNS was ready and remain stuck, delete the ACME orders so cert-manager retries them with the current DNS state:

```bash
kubectl delete order -n envoy-gateway --all
```

---

## Verify TLS Certificates

After DNS propagates, cert-manager will attempt the ACME HTTP-01 challenge. Monitor progress:

**1. Check challenge status:**

```bash
kubectl get challenge -n envoy-gateway
```

Challenges should move from `pending` → disappear (completed). If they stay `pending` for more than 5 minutes, see [Troubleshooting](#troubleshooting).

**2. Check certificate status:**

```bash
kubectl get certificate -n envoy-gateway
```

Both certificates must show `READY: True` before HTTPS works.

**3. Test HTTPS access:**

```bash
curl -v https://launchpad.your-domain.com
```

---

## Create Roles on Stardog for IDP

```bash
NAMESPACE=stardog-ns
RELEASE=stardog

kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role add reader
kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role grant reader -a read -o "*:*"

kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role add writer
kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role grant writer -a write -o "*:*"

kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role add admin
kubectl exec -n $NAMESPACE ${RELEASE}-stardog-0 -- \
  /opt/stardog/bin/stardog-admin role grant admin -a all -o "*:*"
```

---

## Troubleshooting

### Helm Install Fails: certIssuer.clusterScoped

**Error:** `gateway.http.tls.secretNamespace outside the release namespace requires certIssuer.clusterScoped=true`

**Fix:** Add `global.certIssuer.clusterScoped: true` to your values file.

---

### GatewayClass Not Found

`GatewayClass` is cluster-scoped — never use `-n` flag when querying it:

```bash
kubectl get gatewayclass   # correct
kubectl get gatewayclass -n envoy-gateway   # always returns "No resources found"
```

If `kubectl get gatewayclass` returns nothing:

```bash
# Check CRD exists
kubectl get crd gatewayclasses.gateway.networking.k8s.io

# Find where the controller is running
kubectl get pods --all-namespaces | grep envoy-gateway

# Check controller logs
kubectl logs -n "${EG_NAMESPACE}" deployment/envoy-gateway
```

---

### Gateway Not Found in stardog-ns

The Gateway is created in the `envoy-gateway` namespace, not `stardog-ns`. Always check:

```bash
kubectl get gateway -n envoy-gateway          # correct
kubectl get gateway -n stardog-ns             # will return "No resources found"
kubectl get gateway --all-namespaces          # shows everything
```

---

### ACME Challenges Stuck Pending

**Symptom:** `kubectl get challenge -n envoy-gateway` shows `STATE: pending` for more than 5 minutes. Certificates stay `READY: False`.

**Cause:** cert-manager is creating `Ingress` resources for the HTTP-01 solver, cert-manager was installed without Gateway API support, or the solver is attached to an HTTPS listener instead of the HTTP listener. Envoy Gateway only processes `HTTPRoute` resources for this setup, and ACME HTTP-01 must be reachable on port 80.

**Verify:**

```bash
kubectl get httproute -n envoy-gateway   # should show solver routes — if empty, this is the problem
curl http://launchpad.your-domain.com/.well-known/acme-challenge/  # should return 404, not connection refused
```

**Fix — patch each ClusterIssuer to use `gatewayHTTPRoute` on the HTTP listeners:**

```bash
kubectl edit clusterissuer stardog-certissuer-lp
kubectl edit clusterissuer stardog-certissuer-sd
```

Replace the `solvers` section in each with:

```yaml
    solvers:
      - selector:
          dnsNames:
            - "sparql.your-domain.com"
        http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: stardog-gateway
                namespace: envoy-gateway
                kind: Gateway
                sectionName: sparql-http
      - selector:
          dnsNames:
            - "launchpad.your-domain.com"
        http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: stardog-gateway
                namespace: envoy-gateway
                kind: Gateway
                sectionName: launchpad-http
```

Delete the stuck challenges to force a retry:

```bash
kubectl delete order -n envoy-gateway --all
kubectl get certificate -n envoy-gateway -w   # watch until READY: True
```

---

### GatewayClass Not Accepted (no accepted gatewayclass in logs)

The Envoy Gateway controller repeatedly logs `no accepted gatewayclass`. This means no `GatewayClass` with `controllerName: gateway.envoyproxy.io/gatewayclass-controller` exists or has been accepted yet.

```bash
# Check both GatewayClasses exist
kubectl get gatewayclass

# Check stardog-envoy-gateway-class is accepted
kubectl describe gatewayclass stardog-envoy-gateway-class | grep -A5 "Conditions"
```

If `stardog-envoy-gateway-class` is missing, re-run Step 5 of the Envoy Gateway installation.

---

### Pods Not Starting in stardog-ns

```bash
# Check pod status and events
kubectl describe pod <pod-name> -n stardog-ns

# Check all events in the namespace
kubectl get events -n stardog-ns --sort-by=.metadata.creationTimestamp
```

---

*Generated from real deployment experience on AKS with kube-stardog-stack v1.1.2 and Envoy Gateway v1.8.1.*

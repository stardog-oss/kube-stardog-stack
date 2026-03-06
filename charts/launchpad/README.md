# Launchpad Helm Chart

This Helm chart deploys Stardog Launchpad, a login service for Stardog endpoints for access to Stardog Applications (Designer, Explorer, and Studio).

## Prerequisites

- An SSO provider to log users in with (e.g. Microsoft Entra)
- A Stardog endpoint to connect to

See the full Launchpad documentation [here](https://github.com/stardog-union/launchpad-docs).

## Installation

### Basic Installation

```bash
helm install my-launchpad ./charts/launchpad
```

### Installation with Custom Values

```bash
helm install my-launchpad ./charts/launchpad -f values.yaml
```

### Installation in a Specific Namespace

```bash
helm install my-launchpad ./charts/launchpad --namespace my-namespace --create-namespace
```

## Configuration

The following table lists the configurable parameters of the Launchpad chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Launchpad replicas | `1` |
| `image.registry` | Container registry | `stardog.azurecr.io` |
| `image.repository` | Container image repository | `sa-lab-stardog/launchpad` |
| `image.tag` | Container image tag | `v3.0.0` |
| `image.pullPolicy` | Container image pull policy | `IfNotPresent` |
| `image.username` | Registry username | `""` |
| `image.password` | Registry password | `""` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `8080` |
| `ingress.enabled` | Deprecated ingress toggle (prefer `gateway.*`) | `false` |
| `ingress.className` | Ingress class name | `nginx` |
| `ingress.url` | Ingress URL | `launchpad.stardogcloud.com` |
| `ingress.path` | Ingress path | `/` |
| `ingress.pathType` | Ingress path type | `Prefix` |
| `gateway.*` | Enable Gateway API (e.g., Envoy Gateway) exposure instead of classic ingress | See `values.yaml` |
| `persistence.storageClass` | Storage class for PVC | `""` |
| `persistence.size` | Size of data volume | `1Gi` |
| `resources.requests.cpu` | CPU resource requests | `500m` |
| `resources.requests.memory` | Memory resource requests | `1Gi` |
| `resources.limits.cpu` | CPU resource limits | `1000m` |
| `resources.limits.memory` | Memory resource limits | `2Gi` |
| `serviceAccount.create` | Whether to create a Launchpad-specific service account | `true` |
| `serviceAccount.name` | Use an existing service account instead of creating one | `""` |
| `serviceAccount.annotations` | Extra annotations on the managed service account | `{}` |
| `nodeSelector` | Node labels to pin Launchpad pods | `{}` |
| `tolerations` | Taints Launchpad pods tolerate; coordinate with `nodeSelector` | `[]` |
| `affinity` | Custom pod affinity/anti-affinity rules | `{}` |
| `securityContext.*` | Pod-level security context (seccomp, UID/GID, fsGroup) | See `values.yaml` |
| `containerSecurityContext.*` | Container-level security context (readOnlyRootFilesystem, privilege escalation) | See `values.yaml` |

### Environment Variables

The chart supports various environment variables for configuration. These can be set in the `env` section of your values file:

#### Basic Configuration
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `FRIENDLY_NAME` | The name you want to display in Launchpad landing page | `"Stardog Applications"` | No |
| `COOKIE_SECRET` | Used to set the secret used to sign cookies in Launchpad. This should be a large, random string | Auto-generated | Yes |
| `SESSION_EXPIRATION` | Used to set the expiration time in seconds for user sessions in Launchpad | `43200` | No |
| `BASE_URL` | Base URL for the application (auto-detected from ingress/gateway; set explicitly when both are disabled) | Auto-detected | No |
| `SECURE` | Enable secure mode | `true` | No |

#### Stardog Endpoint Configuration
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `STARDOG_INTERNAL_ENDPOINT` | Internal Stardog endpoint URL | Auto-configured in umbrella chart | Yes |
| `STARDOG_EXTERNAL_ENDPOINT` | External Stardog endpoint URL | Auto-configured in umbrella chart | Yes |

#### Authentication Configuration
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `PASSWORD_AUTH_ENABLED` | Enable password authentication | `false` | No |
| `AZURE_AUTH_ENABLED` | Enable Azure authentication | `false` | No |
| `GOOGLE_AUTH_ENABLED` | Enable Google authentication | `false` | No |
| `KEYCLOAK_AUTH_ENABLED` | Enable Keycloak authentication | `false` | No |

#### Azure Authentication (when `AZURE_AUTH_ENABLED=true`)
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `AZURE_TENANT` | The Tenant ID of the Microsoft Entra ID used | `""` | Yes |
| `AZURE_CLIENT_ID` | The application ID that Launchpad is registered with | `""` | Yes |
| `AZURE_CLIENT_SECRET` | The secret for the Launchpad application | `""` | Yes |
| `AZURE_GOV_CLOUD_US` | Used to set the Azure cloud environment to the Azure US Government Cloud | `false` | No |

#### SSO Connection Configuration
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `SSOCONNECTION_TEST_AZURE_CLIENT_ID` | The application ID for SSO connection testing | `""` | No |
| `SSOCONNECTION_TEST_AZURE_CLIENT_SECRET` | The secret for SSO connection testing | `""` | No |
| `SSOCONNECTION_TEST_AZURE_TENANT` | The Tenant ID for SSO connection testing | `""` | No |
| `SSOCONNECTION_TEST_AZURE_DISPLAY_NAME` | Display name for SSO connection testing | `"Development Test"` | No |
| `SSOCONNECTION_TEST_AZURE_STARDOG_ENDPOINT` | Stardog endpoint for SSO connection testing | `""` | No |

#### Voicebox Integration (when using umbrella chart)
| Environment Variable | Description | Default | Required |
|---------------------|-------------|---------|----------|
| `VOICEBOX_SERVICE_ENDPOINT` | Voicebox service endpoint URL | Auto-configured in umbrella chart | No |

### Example Configuration

```yaml
launchpad:
  enabled: true
  env:
    # Basic configuration
    FRIENDLY_NAME: "My Stardog Applications"
    COOKIE_SECRET: "your-secure-cookie-secret-here"
    SESSION_EXPIRATION: "43200"
    
    # Azure authentication
    AZURE_AUTH_ENABLED: "true"
    AZURE_TENANT: "your-tenant-id"
    AZURE_CLIENT_ID: "your-client-id"
    AZURE_CLIENT_SECRET: "your-client-secret"
    
    # SSO connection for Stardog endpoints
    SSOCONNECTION_TEST_AZURE_CLIENT_ID: "your-sparql-client-id"
    SSOCONNECTION_TEST_AZURE_CLIENT_SECRET: "your-sparql-client-secret"
    SSOCONNECTION_TEST_AZURE_TENANT: "your-tenant-id"
    SSOCONNECTION_TEST_AZURE_DISPLAY_NAME: "Development Test"
    SSOCONNECTION_TEST_AZURE_STARDOG_ENDPOINT: "https://sparql.your-domain.com"
```

### Environment Variable Generation

For the `COOKIE_SECRET`, you can generate a secure random string using:

```bash
# Generate a 32-byte random string and encode as base64
head -c32 /dev/urandom | base64
```

### Operational Settings

Launchpad shares the same scheduling helpers as the rest of the stack. Combine `nodeSelector` and `tolerations` to place the pods on pre-tainted pools, and either let the chart create a scoped service account (`serviceAccount.create=true`) or point at an existing identity via `serviceAccount.name` when cluster administrators manage RBAC centrally. All of the defaults follow Kubernetes hardening guidance (RuntimeDefault seccomp, non-root UID/GID 100000, and a read-only root filesystem), so only override the security context knobs when the container image explicitly requires it.

### Gateway API (Envoy Gateway) exposure

Clusters running Envoy Gateway (recommended) or another Gateway API controller can skip the legacy ingress objects entirely:

```yaml
gateway:
  enabled: true
  http:
    domain: example.com
    createGateway: true
    tls:
      enabled: true
      secretName: launchpad-gateway-cert
    redirect:
      enabled: true
```

Set `gateway.http.domain` to the base domain (e.g., `example.com`) so the chart can derive the Launchpad hostname (`launchpad.example.com`). Disable `ingress.enabled` when turning on the block above. The chart creates a Gateway and HTTPRoute targeting the Launchpad service; provide a TLS secret so Envoy Gateway can terminate HTTPS. If `certIssuer.enabled=true` and you leave `gateway.http.tls.secretName` empty, the chart automatically reuses the cert-manager secret that ingress consumed (`launchpad-<release>-tls` by default).

ACME issuers automatically add HTTP-01 solvers for whichever exposure (ingress or gateway) you enable. When `gateway.http.redirect.enabled=true` and redirect parentRefs are set, the solver targets those HTTP listener parentRefs so HTTP-01 can complete. Override `certIssuer.acme.solvers` if you need to force DNS-01 or supply custom solver options.

> **Ingress deprecation:** The `ingress.*` options are maintained only for backwards compatibility, emit a warning during rendering, and will be removed after Gateway adoption is complete.

## Usage

### Basic Usage

1. Install the chart:
   ```bash
   helm install my-launchpad ./charts/launchpad
   ```

2. Access Launchpad at `http://launchpad.your-domain.com`.

## Upgrading

```bash
helm upgrade my-launchpad ./charts/launchpad
```

## Uninstalling

```bash
helm uninstall my-launchpad
```

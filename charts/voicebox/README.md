# Voicebox Helm Chart

This Helm chart deploys Stardog Voicebox, our conversational AI chat interface for your Enterprise Data.

## Prerequisites

- A Stardog endpoint
- Azure OpenAI or other LLM provider credentials (for AI functionality)

## Installation

### Basic Installation

```bash
helm install my-voicebox ./charts/voicebox
```

### Installation with Custom Values

```bash
helm install my-voicebox ./charts/voicebox -f values.yaml
```

### Installation in a Specific Namespace

```bash
helm install my-voicebox ./charts/voicebox --namespace my-namespace --create-namespace
```

## Configuration

The following table lists the configurable parameters of the Voicebox chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Voicebox replicas | `1` |
| `image.registry` | Container registry | `stardog.azurecr.io` |
| `image.repository` | Container image repository | `sa-lab-stardog/voicebox` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Container image pull policy | `IfNotPresent` |
| `image.username` | Registry username | `""` |
| `image.password` | Registry password | `""` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `8080` |
| `configFile` | Voicebox configuration JSON | `""` |
| `environmentVariables.AZURE_API_KEY` | Azure API key | `"azure-api-key"` |
| `environmentVariables.PRODUCTION` | Production mode flag | `1` |
| `securityContext.*` | Pod-level security context (seccomp, UID/GID, fsGroup) | See `values.yaml` |
| `containerSecurityContext.*` | Container-level security context (readOnlyRootFilesystem, privilege escalation) | See `values.yaml` |
| `resources.requests/limits.*` | CPU/memory reservations and limits | `500m/1Gi` requests, `1 vCPU/2Gi` limits |
| `nodeSelector` | Node labels to pin Voicebox pods | `{}` |
| `tolerations` | Taints Voicebox pods tolerate; coordinate with `nodeSelector` | `[]` |
| `affinity` | Custom pod affinity/anti-affinity rules | `{}` |

### Configuration File

The `configFile` parameter allows you to configure Voicebox behavior. Example configuration:

```json
{
  "agent_selection_type": "llm",
  "enable_lineage": true,
  "enable_external_llm": true,
  "enable_analytics": true,
  "enable_charts": true,
  "use_agents_automatically": false,
  "default_llm_config": {
    "llm_provider": "azure",
    "llm_name": "Meta-Llama-3.1-70B-Instruct",
    "server_url": "https://your-model.services.ai.azure.com/models"
  }
}
```

**Supported Llama Models:**
- `Meta-Llama-3.1-70B-Instruct`
- `Meta-Llama-3.3-70B-Instruct`

### Environment Variables

The chart supports various environment variables:

- `AZURE_API_KEY`: Azure OpenAI API key
- `PRODUCTION`: Set to 1 for production, 0 for development

### Operational Settings

Voicebox inherits the same hardened defaults as the other subcharts. Use `nodeSelector`/`tolerations` to schedule the workload onto GPU or high-memory pools when needed, and adjust `resources` to match the compute profile of your LLM provider. The security context defaults keep the container non-root with RuntimeDefault seccomp and a read-only filesystem; override them only if your custom images require additional capabilities.

## Usage

### Basic Usage

1. Install the chart:
   ```bash
   helm install my-voicebox ./charts/voicebox
   ```

2. Access Voicebox by clicking on the sidebar while using the Stardog apps or from Launchpad's landing page.

## Upgrading

```bash
helm upgrade my-voicebox ./charts/voicebox
```

## Uninstalling

```bash
helm uninstall my-voicebox
```

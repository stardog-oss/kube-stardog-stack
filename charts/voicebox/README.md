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
| `bitesService.enabled` | Enable Spark-based Bites integration | `false` |
| `bitesService.image.registry` | Bites container registry | `docker.io` |
| `bitesService.image.repository` | Bites container image repository | `stardog/voicebox-bites` |
| `bitesService.image.tag` | Bites container image tag | `latest` |
| `bitesService.image.pullPolicy` | Bites image pull policy | `IfNotPresent` |
| `bitesService.image.username` | Bites registry username | `""` |
| `bitesService.image.password` | Bites registry password | `""` |
| `bitesService.sparkApplication.name` | SparkApplication name for Bites job | `voicebox-bites-job` |
| `bitesService.sparkApplication.sparkVersion` | Spark version for Bites job | `"3.5.0"` |
| `bitesService.sparkApplication.pythonVersion` | Python version for Spark job | `"3"` |
| `bitesService.sparkApplication.mode` | Spark deployment mode | `cluster` |
| `bitesService.sparkApplication.type` | Spark application type | `Python` |
| `bitesService.sparkApplication.mainApplicationFile` | Main Spark application file path | `local:///app/src/voicebox_bites/etl/bulk_document_extraction.py` |
| `bitesService.sparkApplication.sparkConf` | Spark configuration map | See `values.yaml` |
| `bitesService.sparkApplication.volumes` | Spark volumes mounted for document input | See `values.yaml` |
| `bitesService.sparkApplication.persistentVolumeClaim.name` | PVC name used by Bites | `voicebox-bites-docs-pvc` |
| `bitesService.sparkApplication.persistentVolumeClaim.size` | PVC size used by Bites | `"20Gi"` |
| `bitesService.sparkApplication.persistentVolumeClaim.storageClassName` | PVC storage class (must support `ReadOnlyMany`; empty uses cluster default) | `""` |
| `bitesService.sparkApplication.driver.cores` | Spark driver cores | `2` |
| `bitesService.sparkApplication.driver.coreLimit` | Spark driver CPU limit | `"2000m"` |
| `bitesService.sparkApplication.driver.memory` | Spark driver memory | `"4g"` |
| `bitesService.sparkApplication.driver.securityContext.*` | Spark driver security settings | See `values.yaml` |
| `bitesService.sparkApplication.executor.cores` | Spark executor cores | `2` |
| `bitesService.sparkApplication.executor.instances` | Spark executor instance count | `3` |
| `bitesService.sparkApplication.executor.memory` | Spark executor memory | `"4g"` |
| `bitesService.sparkApplication.executor.securityContext.*` | Spark executor security settings | See `values.yaml` |
| `bitesService.sparkApplication.restartPolicy.type` | Spark restart policy | `Never` |

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

## Bites Service (Spark Integration)

The Voicebox Bites Service enables Spark-based document processing capabilities within the Voicebox application. It uses the Spark Operator to run Spark applications on Kubernetes for ETL operations like bulk document extraction.

### Prerequisites

Before enabling the Bites Service, you must install the Spark Operator in your Kubernetes cluster. The Spark Operator manages Spark applications as native Kubernetes resources.

#### Install Spark Operator

Use the following Helm command to install the Spark Operator:

Add the Helm repository
```bash
helm repo add --force-update spark-operator https://kubeflow.github.io/spark-operator
```

```bash
helm upgrade -i spark-operator spark-operator/spark-operator \
  -n spark-operator \
  --create-namespace \
  --set spark.jobNamespaces[0]=<namespace_where_stardog_is> \
  --set hook.upgradeCrd=true \
  --set webhook.enable=true
```

Replace `<namespace_where_stardog_is>` with the actual namespace where your Stardog deployment is running (e.g., `stardog`).

**Important Notes:**
- The `spark.jobNamespaces[0]` setting restricts Spark jobs to run only in the specified namespace for security.
- `hook.upgradeCrd=true` ensures CRDs are updated during upgrades.
- `webhook.enable=true` enables validation webhooks for SparkApplication resources.

For more details on installing and configuring the Spark Operator, please refer to the [official documentation](https://github.com/kubeflow/spark-operator).

Verify the installation:
```bash
kubectl get pods -n spark-operator
kubectl get crd sparkapplications.sparkoperator.k8s.io
```

### Bites Service Configuration

Enable the Bites Service by setting the following values in your `values.yaml`:

```yaml
bitesService:
  enabled: true
  image:
    registry: docker.io
    repository: stardog/voicebox-bites
    tag: latest
    pullPolicy: IfNotPresent

  sparkApplication:
    enabled: true
    name: voicebox-bites-job
    sparkVersion: "3.5.0"
    pythonVersion: "3"
    mode: cluster
    type: Python
    mainApplicationFile: "local:///app/src/voicebox_bites/etl/bulk_document_extraction.py"

    # PVC Configuration for document storage
    persistentVolumeClaim:
      name: voicebox-bites-docs-pvc
      size: "20Gi"
      storageClassName: ""  # Uses default storage class (must support ReadOnlyMany)

    # Spark Configuration
    sparkConf:
      "spark.jars.ivy": "/tmp/.ivy2"
      "spark.local.dir": "/tmp/spark-local"

    # Driver and Executor settings
    driver:
      cores: 2
      coreLimit: "2000m"
      memory: "4g"
    executor:
      cores: 2
      instances: 3
      memory: "4g"

    restartPolicy:
      type: Never
```

The storage class selected for `bitesService.sparkApplication.persistentVolumeClaim.storageClassName` must support the `ReadOnlyMany` access mode.

#### User Token Permissions

The user token used for testing the Bites Service must have the following permissions:

- **Database Permissions** (for each database):
  - `db:online` / `db:offline` - To bring databases online/offline
  - `db:write` - To write data to databases
  - `db:metadata:write` - To modify database metadata
- **Server Permissions**:
  - `db:list` - To list available databases

Example Stardog role configuration:
```bash
# Create a role with required permissions
stardog-admin role create bites-user-role

# Grant database permissions (replace <database> with actual database names)
stardog-admin role grant -r bites-user-role db:online <database>
stardog-admin role grant -r bites-user-role db:offline <database>
stardog-admin role grant -r bites-user-role db:write <database>
stardog-admin role grant -r bites-user-role db:metadata:write <database>

# Grant server permissions
stardog-admin role grant -r bites-user-role db:list

# Assign role to user
stardog-admin user grant-role -u <test-user> bites-user-role
```

### Bites Service Installation

Install or upgrade the Voicebox chart with Bites Service enabled:

```bash
helm upgrade -i voicebox ./charts/voicebox \
  --set bitesService.enabled=true \
  --namespace <your-namespace>
```

### Bites Service Usage

Once installed, the Bites Service will:

1. Create a PersistentVolumeClaim for document storage
2. Deploy a SparkApplication that runs the bulk document extraction job
3. Mount the document volume for read-only access

Monitor the Spark job:
```bash
kubectl get sparkapplications
kubectl describe sparkapplication voicebox-bites-job
kubectl logs -f <spark-driver-pod>
```

### Bites Service Troubleshooting

- **Spark Operator not found**: Ensure the Spark Operator is installed and the namespace is allowed in `spark.jobNamespaces`.
- **PVC creation fails**: Check storage class availability/permissions and confirm it supports `ReadOnlyMany`.
- **Spark job fails**: Review SparkApplication logs and ensure the main application file path is correct.

### Bites Service Security Considerations

- The service runs with non-root security contexts
- Spark jobs are restricted to the specified namespace
- Document volumes are mounted read-only for security

For more information about Bites, please refer to the full documentation: [Using Unstructured Data with Voicebox](https://docs.stardog.com/voicebox/using-unstructured-data-with-voicebox/#overview)

## Upgrading

```bash
helm upgrade my-voicebox ./charts/voicebox
```

## Uninstalling

```bash
helm uninstall my-voicebox
```

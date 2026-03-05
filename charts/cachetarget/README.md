Stardog Cache Target Helm Chart
===============================

This chart installs a Stardog Cache Target. You must deploy a Stardog cluster
before deploying the cache target.

Chart Details
-------------

This chart deploys a cache target node in k8s and registers the cache target
with a Stardog Cluster deployment in the same namespace.

Configuration Parameters
------------------------

| Parameter                                    | Description |
| ---                                          | --- |
| `fullnameOverride`                           | The k8s name for the Stardog deployment |
| `namespaceOverride`                          | The k8s namespace for the Stardog deployment (single node only) |
| `admin.password`                             | Stardog admin password |
| `admin.passwordSecretRef`                    | A reference to an external Stardog admin password secret (if set, `admin.password` will be ignored) |
| `javaArgs`                                   | Java args for Stardog server |
| `image.registry`                             | The Docker registry containing the Stardog image |
| `image.repository`                           | The Docker image repository containing the Stardog image  |
| `image.pullPolicy`                           | The Docker image pullPolicy for Stardog |
| `image.tag`                                  | The Docker image tag for Stardog |
| `image.username`                             | The Docker registry username |
| `image.password`                             | The Docker registry password |
| `persistence.storageClass`                   | The storage class to use for Stardog home volumes |
| `persistence.size`                           | The size of volume for Stardog home |
| `stardogHome`                                | Path to Stardog home inside the container (defaults `/var/opt/stardog`) |
| `jvm.minHeap`                                | Minimum JVM heap size (e.g. `1g`) |
| `jvm.maxHeap`                                | Maximum JVM heap size |
| `jvm.directMem`                              | Direct memory size passed via `-XX:MaxDirectMemorySize` |
| `ports.server`                               | The port to expose Stardog server |
| `javaArgs`                                   | Additional JVM arguments appended to the defaults |
| `waitForStartSeconds`                        | How long the post-install hook waits for the cache pod to come online before registering |
| `tmpDir.path`                                | Base path used for `java.io.tmpdir`. Defaults to `/var/opt/stardog/tmp-123456789`. |
| `tmpDir.local`                               | When `true` (default) the chart provisions an `emptyDir` volume at `tmpDir.path`. Set `false` when the path already resides inside `stardogHome`. |
| `log4jConfig.override`                       | Whether to override the default log4j config |
| `log4jConfig.content`                        | The new log4j configuration |
| `securityContext.*`                          | Pod-level security context (defaults to run as non-root UID/GID 100000, RuntimeDefault seccomp, fsGroup 100000) |
| `containerSecurityContext.allowPrivilegeEscalation` | Whether the container may escalate privileges (default: `false`) |
| `containerSecurityContext.readOnlyRootFilesystem`   | Mount container filesystem read-only (default: `true`) |
| `additionalStardogProperties`                | Allow adding additional settings to stardog.properties file |
| `environmentVariables`                       | Extra environment variables injected into the cache target container |
| `primary.name`                               | The name of the primary Stardog release to register the target with (defaults to `stardog-<release>`) |
| `primary.namespace`                          | Override the namespace that hosts the primary cluster (defaults to this release namespace) |
| `primary.port`                               | The port of the primary Stardog service to register the target with (defaults to `5820`) |
| `primary.url`                                | Optional HTTPS endpoint for an externally managed cluster |
| `primary.validateService`                    | Fail rendering when the target Stardog Service is missing (default: `false`) |
| `primary.validateConnectivity`               | Have the post-install job curl the primary endpoint before registering |
| `primary.skipTLSVerify`                      | Skips TLS verification when `primary.url` points at a self-signed endpoint |
| `serviceAccount.create`                      | Whether to create a dedicated service account (default: `true`) |
| `serviceAccount.name`                        | Use an existing service account instead of creating one |
| `serviceAccount.annotations`                 | Extra annotations for the service account when it is created |
| `nodeSelector`                               | Node labels to pin cache pods to specific node pools |
| `tolerations`                                | Taints the pods tolerate; match with `nodeSelector` to target dedicated pools |

The default values are specified in `values.yaml`.

### Temporary storage (tmpDir)

`tmpDir.path` replaces the older string-only value. When `tmpDir.local=true` the chart provisions an `emptyDir` that lives on the same node as the cache target pod, ensuring high-throughput scratch storage. Set `tmpDir.local=false` when the temporary directory should live on the persistent volume instead.

### Cache target registration workflow

After the StatefulSet is created a hook job waits `waitForStartSeconds` for the cache pod to become healthy, changes the admin password, then calls `setup_cache_target` to register with the primary server. Use the `primary.*` options to point at a different namespace or at an external HTTPS endpoint (`primary.url`). `primary.validateService` validates that the in-cluster Service exists at template time, while `primary.validateConnectivity` and `primary.skipTLSVerify` control runtime connectivity checks performed by the job.

### Node placement and service accounts

`nodeSelector`/`tolerations` feed a shared helper so the StatefulSet and hook job land on the right nodes. The same service account (created automatically by default) runs both workloads; set `serviceAccount.create=false` and `serviceAccount.name` to leverage an existing identity with custom permissions.

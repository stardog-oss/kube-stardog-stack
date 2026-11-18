# Push a Stardog Image to a Private Registry Using Docker

If your cluster cannot pull directly from Docker Hub or Stardog's image registry, mirror the required image into your private registry and point the Helm chart at that registry. Run the Docker commands from a machine that can reach both registries.

This example uses Stardog `12.2.0` throughout. Replace the version consistently with the version you intend to deploy, and replace `myregistry.example.com` with your registry hostname.

## Pull the Source Image

```bash
docker pull stardog/stardog:12.2.0
```

## Tag the Image

```bash
docker tag stardog/stardog:12.2.0 myregistry.example.com/stardog:12.2.0
```

## Push the Image

```bash
docker login myregistry.example.com
docker push myregistry.example.com/stardog:12.2.0
```

## Update Helm Values

Save the following as `values.yaml` for a standalone Stardog server installed through the umbrella chart. This example disables Launchpad, Voicebox, and ZooKeeper so their images are not pulled from public registries.

```yaml
global:
  launchpad:
    enabled: false
  voicebox:
    enabled: false
  zookeeper:
    enabled: false

stardog:
  cluster:
    enabled: false
  image:
    registry: myregistry.example.com
    repository: stardog
    tag: "12.2.0"
```

For the standalone Stardog chart, use only the contents under `stardog:` and omit the outer `stardog:` key. Configure the cluster's image pull credentials for your registry before deploying.

If your deployment enables Launchpad, Voicebox, ZooKeeper, Cache Target, or other workloads, mirror every enabled component's container and init-container images and configure their image values as well. Mirroring only Stardog does not make a multi-component deployment independent of public registries.

Validate with:

```bash
helm template <release> <chart> -n <namespace> -f values.yaml
```

Inspect all rendered `image:` references to confirm that each enabled workload uses an accessible registry. Keep the normal license, storage, and other environment-specific values required by your deployment.

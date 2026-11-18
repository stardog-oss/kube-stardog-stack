# Push a Stardog Image to a Private Registry Using Azure ACR Build

If your cluster cannot pull directly from Docker Hub or Stardog's image registry, mirror the required image into Azure Container Registry and point the Helm chart at that registry.

## Create a Dockerfile

```dockerfile
FROM stardog/stardog:<tag>
```

## Build the Image in ACR

```bash
az acr build \
  --registry <acr-name> \
  --image stardog/stardog:<tag> \
  --file Dockerfile \
  .
```

Example:

```bash
az acr build \
  --registry mystardogregistry \
  --image stardog/stardog:latest \
  --file Dockerfile \
  .
```

ACR Tasks must be able to pull the image in the Dockerfile `FROM` line. If the source image is in a private registry, configure registry access for ACR Tasks before running the build.

## Configure Pull Access

For an AKS cluster using an ACR registry with the standard RBAC permissions mode, attach the registry:

```bash
az aks update --name <aks-cluster-name> --resource-group <resource-group> --attach-acr <acr-name>
```

For ABAC-enabled registries (`RBAC Registry + ABAC Repository Permissions`), `--attach-acr` is not supported. Assign the `Container Registry Repository Reader` role on the registry to the AKS kubelet managed identity instead. See [AKS and ACR integration](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration) for the role assignment procedure.

Alternatively, configure an image pull secret with credentials authorized to pull the image.

## Update Helm Values

Set the chart image values to the ACR image. The exact keys depend on whether you are configuring the Stardog subchart directly or through the umbrella chart.

```yaml
stardog:
  image:
    registry: <acr-name>.azurecr.io
    repository: stardog/stardog
    tag: <tag>
```

For the standalone Stardog chart, omit the outer `stardog:` key.

Validate with:

```bash
helm template <release> <chart> -n <namespace> -f values.yaml
```

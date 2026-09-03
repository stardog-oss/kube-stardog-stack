# Push an Image to Your Own Container Registry

If your cluster cannot pull directly from Docker Hub or Stardog's image registry, mirror the required image into your private registry and point the Helm chart at that registry.

## Pull the Source Image

```bash
docker pull stardog/stardog:<tag>
```

## Tag the Image

```bash
docker tag stardog/stardog:<tag> <private-registry>/<repository>:<tag>
```

Example:

```bash
docker tag stardog/stardog:latest myregistry.example.com/stardog:latest
```

## Push the Image

```bash
docker login <private-registry>
docker push <private-registry>/<repository>:<tag>
```

## Update Helm Values

Set the chart image values to the private registry image. The exact keys depend on whether you are configuring the Stardog subchart directly or through the umbrella chart.

Validate with:

```bash
helm template <release> <chart> -n <namespace> -f values.yaml
```

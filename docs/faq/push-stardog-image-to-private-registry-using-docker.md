# Push a Stardog Image to a Private Registry Using Docker

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

For the umbrella chart, set the image values to match the repository and tag you pushed. For example, for `myregistry.example.com/stardog:12.2.0`:

```yaml
stardog:
  image:
    registry: myregistry.example.com
    repository: stardog
    tag: "12.2.0"
```

For the standalone Stardog chart, omit the outer `stardog:` key. Configure the cluster's image pull credentials for your registry before deploying.

Validate with:

```bash
helm template <release> <chart> -n <namespace> -f values.yaml
```

# Secret Management With Azure Key Vault

This guide shows the flow for loading runtime secrets from Azure Key Vault into Stardog Stack Helm charts by using the Secrets Store CSI driver.

The same pattern works for `stardog`, `launchpad`, and `voicebox`.

## Flow

1. Store secrets in Azure Key Vault.
2. Configure `secretProviderClass` in Helm values.
3. Map Key Vault secret names to Kubernetes Secret keys.
4. Sync the values into a Kubernetes Secret.
5. Mount the SecretProviderClass with the CSI driver.
6. Load the synced Kubernetes Secret into the container with `envFrom`.
7. Verify the rendered resources and running pod.

## Naming Rule

Azure Key Vault secret names do not support underscores. Use hyphens in Key Vault and map them to underscore-based Kubernetes Secret keys.

```yaml
objectName: AZURE-CLIENT-SECRET   # Azure Key Vault secret name
key: AZURE_CLIENT_SECRET           # Kubernetes Secret key and environment variable
```

This lets the application receive standard environment variable names while Key Vault uses valid secret names.

## Step 1: Create Secrets In Azure Key Vault

Example for Launchpad:

```bash
az keyvault secret set --vault-name <key-vault-name> --name AZURE-CLIENT-ID --value "<client-id>"
az keyvault secret set --vault-name <key-vault-name> --name AZURE-CLIENT-SECRET --value "<client-secret>"
az keyvault secret set --vault-name <key-vault-name> --name AZURE-TENANT --value "<tenant-id>"
az keyvault secret set --vault-name <key-vault-name> --name SSOCONNECTION-DEVELOPMENT-AZURE-CLIENT-ID --value "<sso-client-id>"
az keyvault secret set --vault-name <key-vault-name> --name SSOCONNECTION-DEVELOPMENT-AZURE-TENANT --value "<tenant-id>"
```

Do not commit real secret values into Helm values files.

## Step 2: Configure Workload Identity

If AKS Workload Identity is used, annotate the chart service account and label the pod template.

```yaml
launchpad:
  serviceAccount:
    annotations:
      azure.workload.identity/client-id: "<workload-identity-client-id>"

  podLabels:
    azure.workload.identity/use: "true"
```

Use the same pattern for `stardog` or `voicebox` by replacing the top-level key.

## Step 3: Configure The SecretProviderClass

The chart can render a `SecretProviderClass` when `secretProviderClass.enabled=true`.

Example for Launchpad:

```yaml
launchpad:
  secretProviderClass:
    enabled: true
    name: launchpad-keyvault
    provider: azure
    secretObjects:
      - secretName: launchpad-runtime-env
        type: Opaque
        data:
          - objectName: AZURE-CLIENT-ID
            key: AZURE_CLIENT_ID
          - objectName: AZURE-CLIENT-SECRET
            key: AZURE_CLIENT_SECRET
          - objectName: AZURE-TENANT
            key: AZURE_TENANT
          - objectName: SSOCONNECTION-DEVELOPMENT-AZURE-CLIENT-ID
            key: SSOCONNECTION_DEVELOPMENT_AZURE_CLIENT_ID
          - objectName: SSOCONNECTION-DEVELOPMENT-AZURE-TENANT
            key: SSOCONNECTION_DEVELOPMENT_AZURE_TENANT
    parameters:
      usePodIdentity: "false"
      useVMManagedIdentity: "false"
      clientID: "<workload-identity-client-id>"
      keyvaultName: "<key-vault-name>"
      tenantId: "<tenant-id>"
      objects: |
        array:
          - |
            objectName: AZURE-CLIENT-ID
            objectType: secret
          - |
            objectName: AZURE-CLIENT-SECRET
            objectType: secret
          - |
            objectName: AZURE-TENANT
            objectType: secret
          - |
            objectName: SSOCONNECTION-DEVELOPMENT-AZURE-CLIENT-ID
            objectType: secret
          - |
            objectName: SSOCONNECTION-DEVELOPMENT-AZURE-TENANT
            objectType: secret
```

The list is intentionally variable. Add or remove entries in both places:

```yaml
secretObjects[0].data:
  - objectName: <vault-secret-name>
    key: <kubernetes-secret-key>

parameters.objects: |
  array:
    - |
      objectName: <vault-secret-name>
      objectType: secret
```

## Step 4: Mount The SecretProviderClass

The CSI driver syncs `secretObjects` into a Kubernetes Secret when a pod mounts the `SecretProviderClass`.

```yaml
launchpad:
  extraVolumes:
    - name: keyvault-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: launchpad-keyvault

  extraVolumeMounts:
    - name: keyvault-secrets
      mountPath: /mnt/secrets-store
      readOnly: true
```

## Step 5: Load The Synced Secret Into The Container

Use `envFrom` to expose every key from the synced Kubernetes Secret as an environment variable.

```yaml
launchpad:
  envFrom:
    - secretRef:
        name: launchpad-runtime-env
```

For one specific key, use `extraEnv`:

```yaml
launchpad:
  extraEnv:
    - name: AZURE_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: launchpad-runtime-env
          key: AZURE_CLIENT_SECRET
```

## Complete Launchpad Example

```yaml
launchpad:
  serviceAccount:
    annotations:
      azure.workload.identity/client-id: "<workload-identity-client-id>"

  podLabels:
    azure.workload.identity/use: "true"

  secretProviderClass:
    enabled: true
    name: launchpad-keyvault
    provider: azure
    secretObjects:
      - secretName: launchpad-runtime-env
        type: Opaque
        data:
          - objectName: AZURE-CLIENT-ID
            key: AZURE_CLIENT_ID
          - objectName: AZURE-CLIENT-SECRET
            key: AZURE_CLIENT_SECRET
          - objectName: AZURE-TENANT
            key: AZURE_TENANT
          - objectName: SSOCONNECTION-DEVELOPMENT-AZURE-CLIENT-ID
            key: SSOCONNECTION_DEVELOPMENT_AZURE_CLIENT_ID
          - objectName: SSOCONNECTION-DEVELOPMENT-AZURE-TENANT
            key: SSOCONNECTION_DEVELOPMENT_AZURE_TENANT
    parameters:
      usePodIdentity: "false"
      useVMManagedIdentity: "false"
      clientID: "<workload-identity-client-id>"
      keyvaultName: "<key-vault-name>"
      tenantId: "<tenant-id>"
      objects: |
        array:
          - |
            objectName: AZURE-CLIENT-ID
            objectType: secret
          - |
            objectName: AZURE-CLIENT-SECRET
            objectType: secret
          - |
            objectName: AZURE-TENANT
            objectType: secret
          - |
            objectName: SSOCONNECTION-DEVELOPMENT-AZURE-CLIENT-ID
            objectType: secret
          - |
            objectName: SSOCONNECTION-DEVELOPMENT-AZURE-TENANT
            objectType: secret

  extraVolumes:
    - name: keyvault-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: launchpad-keyvault

  extraVolumeMounts:
    - name: keyvault-secrets
      mountPath: /mnt/secrets-store
      readOnly: true

  envFrom:
    - secretRef:
        name: launchpad-runtime-env
```

## Stardog And Voicebox Examples

Use the same structure with chart-specific names.

Stardog:

```yaml
stardog:
  secretProviderClass:
    enabled: true
    name: stardog-keyvault
    secretObjects:
      - secretName: stardog-runtime-env
        type: Opaque
        data:
          - objectName: AZURE-CLIENT-SECRET
            key: AZURE_CLIENT_SECRET
    parameters:
      keyvaultName: "<key-vault-name>"
      tenantId: "<tenant-id>"
      objects: |
        array:
          - |
            objectName: AZURE-CLIENT-SECRET
            objectType: secret

  extraVolumes:
    - name: keyvault-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: stardog-keyvault

  extraVolumeMounts:
    - name: keyvault-secrets
      mountPath: /mnt/secrets-store
      readOnly: true

  envFrom:
    - secretRef:
        name: stardog-runtime-env
```

Voicebox:

```yaml
voicebox:
  secretProviderClass:
    enabled: true
    name: voicebox-keyvault
    secretObjects:
      - secretName: voicebox-runtime-env
        type: Opaque
        data:
          - objectName: OPENAI-API-KEY
            key: OPENAI_API_KEY
    parameters:
      keyvaultName: "<key-vault-name>"
      tenantId: "<tenant-id>"
      objects: |
        array:
          - |
            objectName: OPENAI-API-KEY
            objectType: secret

  extraVolumes:
    - name: keyvault-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: voicebox-keyvault

  extraVolumeMounts:
    - name: keyvault-secrets
      mountPath: /mnt/secrets-store
      readOnly: true

  envFrom:
    - secretRef:
        name: voicebox-runtime-env
```

## Step 6: Render And Install

Render first:

```bash
helm template stardog . \
  --namespace stardog-ns \
  --values ./values.yaml
```

Install or upgrade:

```bash
helm upgrade --install stardog . \
  --namespace stardog-ns \
  --create-namespace \
  --values ./values.yaml \
  --timeout 10m
```

## Step 7: Verify

Check the `SecretProviderClass`:

```bash
kubectl get secretproviderclass -n stardog-ns
kubectl describe secretproviderclass launchpad-keyvault -n stardog-ns
```

Check the synced Kubernetes Secret:

```bash
kubectl get secret launchpad-runtime-env -n stardog-ns
```

Check that the workload references the Secret:

```bash
kubectl get statefulset -n stardog-ns -o yaml | grep -A3 envFrom
```

Check mounted files:

```bash
kubectl exec -n stardog-ns <launchpad-pod-name> -- ls -la /mnt/secrets-store
```

## Troubleshooting

If the Kubernetes Secret is missing, check that:

- the pod is running and mounts the CSI volume
- `volumeAttributes.secretProviderClass` matches `secretProviderClass.name`
- every `objectName` exists in Azure Key Vault
- Key Vault names use hyphens, not underscores
- the identity has permission to read the Key Vault secrets
- the Secrets Store CSI driver and Azure provider are installed in the cluster

If environment variables are missing, check that:

- `envFrom.secretRef.name` matches `secretObjects[].secretName`
- `secretObjects[].data[].key` uses the exact environment variable name expected by the application
- the pod was restarted after the synced Kubernetes Secret changed

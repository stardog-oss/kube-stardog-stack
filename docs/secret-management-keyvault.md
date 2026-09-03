# Secret Management With Azure Key Vault

This guide shows the flow for loading runtime secrets from Azure Key Vault into Stardog Stack Helm charts by using the Secrets Store CSI driver.

The same pattern works for `stardog`, `launchpad`, and `voicebox`.

## Flow

1. Store secrets in Azure Key Vault.
2. Create or identify the Azure identity that can read Key Vault.
3. Connect that Azure identity to the Kubernetes ServiceAccount with AKS Workload Identity.
4. Configure `secretProviderClass` in Helm values.
5. Map Key Vault secret names to Kubernetes Secret keys.
6. Sync the values into a Kubernetes Secret.
7. Mount the SecretProviderClass with the CSI driver.
8. Load the synced Kubernetes Secret into the container with `envFrom`.
9. Verify the rendered resources and running pod.

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

## Step 2: Create Or Find The Azure Identity

AKS Workload Identity uses a user-assigned managed identity. If one already exists, get its `clientId` and `principalId`:

```bash
IDENTITY_RESOURCE_GROUP="<identity-resource-group>"
IDENTITY_NAME="<managed-identity-name>"

CLIENT_ID="$(az identity show \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --name "$IDENTITY_NAME" \
  --query clientId \
  --output tsv)"

PRINCIPAL_ID="$(az identity show \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --name "$IDENTITY_NAME" \
  --query principalId \
  --output tsv)"
```

If the identity does not exist, create it first:

```bash
IDENTITY_RESOURCE_GROUP="<identity-resource-group>"
LOCATION="<azure-region>"
IDENTITY_NAME="stardog-keyvault-identity"

az identity create \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --name "$IDENTITY_NAME" \
  --location "$LOCATION"
```

Then get the IDs:

```bash
CLIENT_ID="$(az identity show \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --name "$IDENTITY_NAME" \
  --query clientId \
  --output tsv)"

PRINCIPAL_ID="$(az identity show \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --name "$IDENTITY_NAME" \
  --query principalId \
  --output tsv)"
```

Use `CLIENT_ID` in Helm values. Use `PRINCIPAL_ID` for Azure role assignment.

## Step 3: Grant Key Vault Access

Give the managed identity permission to read secrets from the Key Vault:

```bash
KEYVAULT_NAME="<key-vault-name>"

KEYVAULT_ID="$(az keyvault show \
  --name "$KEYVAULT_NAME" \
  --query id \
  --output tsv)"

az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role "Key Vault Secrets User" \
  --scope "$KEYVAULT_ID"
```

For this environment, the Key Vault name is:

```bash
KEYVAULT_NAME="akv-sdtraining-cmc-32cb"
```

## Step 4: Get The AKS OIDC Issuer

AKS Workload Identity requires the cluster OIDC issuer URL:

```bash
AKS_RESOURCE_GROUP="<aks-resource-group>"
AKS_NAME="<aks-cluster-name>"

OIDC_ISSUER="$(az aks show \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --query oidcIssuerProfile.issuerUrl \
  --output tsv)"
```

If this returns empty, enable OIDC issuer and Workload Identity on the AKS cluster before continuing:

```bash
az aks update \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --name "$AKS_NAME" \
  --enable-oidc-issuer \
  --enable-workload-identity
```

## Step 5: Confirm Helm ServiceAccount Names

Federated credentials must match the exact Kubernetes ServiceAccount subject:

```text
system:serviceaccount:<namespace>:<service-account-name>
```

Render the chart and inspect ServiceAccount names:

```bash
helm template sd-stack . \
  --namespace stardog \
  --values ./values.yaml \
  --set global.skipSecretValidation=true | grep -A6 "kind: ServiceAccount"
```

For a release named `sd-stack`, the default component ServiceAccount names commonly render as:

```text
launchpad-sd-stack
voicebox-sa
stardog-sd-stack
```

Always verify with `helm template`; overrides such as `fullnameOverride` or `serviceAccount.name` can change these names.

If pods already exist, confirm the actual ServiceAccount used by the pod:

```bash
kubectl get pod -n stardog <pod-name> \
  -o jsonpath='{.spec.serviceAccountName}{"\n"}'
```

If Azure returns `AADSTS700213`, use the `presented assertion subject` from the error message as the source of truth. The federated credential subject must match it exactly.

## Step 6: Create Federated Credentials

Create one federated credential per Kubernetes ServiceAccount that needs to read Key Vault.

Launchpad:

```bash
NAMESPACE="stardog"
LAUNCHPAD_SERVICE_ACCOUNT="launchpad-sd-stack"

az identity federated-credential create \
  --name launchpad-keyvault-federation \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:$NAMESPACE:$LAUNCHPAD_SERVICE_ACCOUNT" \
  --audience api://AzureADTokenExchange
```

Voicebox:

```bash
NAMESPACE="stardog"
VOICEBOX_SERVICE_ACCOUNT="voicebox-sa"

az identity federated-credential create \
  --name voicebox-keyvault-federation \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:$NAMESPACE:$VOICEBOX_SERVICE_ACCOUNT" \
  --audience api://AzureADTokenExchange
```

Stardog, if needed:

```bash
NAMESPACE="stardog"
STARDOG_SERVICE_ACCOUNT="stardog-sd-stack"

az identity federated-credential create \
  --name stardog-keyvault-federation \
  --identity-name "$IDENTITY_NAME" \
  --resource-group "$IDENTITY_RESOURCE_GROUP" \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:$NAMESPACE:$STARDOG_SERVICE_ACCOUNT" \
  --audience api://AzureADTokenExchange
```

## Step 7: Configure Workload Identity In Helm Values

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

Use the same `CLIENT_ID` in `secretProviderClass.parameters.clientID`.

## Step 8: Configure The SecretProviderClass

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

## Step 9: Mount The SecretProviderClass

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

## Step 10: Load The Synced Secret Into The Container

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

## Step 11: Render And Install

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

## Step 12: Verify

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

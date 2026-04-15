# Edit LDAP Roles When Using the Helm Chart

Do not make persistent LDAP role changes by editing the running pod or the live ConfigMap directly. Those changes can be overwritten when the pod restarts or when Helm reconciles the release.

Update the chart values or chart template that produces the Stardog configuration containing `ldap.role.mappings`, then apply the change with Helm.

## Recommended Workflow

1. Locate the `ldap.role.mappings` value in your Helm values or chart configuration.
2. Update the mapping in source control.
3. Render or diff the release before applying:

```bash
helm template <release> <chart> -n <namespace> -f values.yaml
helm diff upgrade <release> <chart> -n <namespace> -f values.yaml
```

4. Apply the change:

```bash
helm upgrade --install <release> <chart> -n <namespace> -f values.yaml
```

5. Restart affected pods if the application does not reload the configuration automatically.

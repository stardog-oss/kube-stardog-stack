# Set the Time Zone in Kubernetes Pods

This is a Kubernetes and container runtime concern, not a Stardog-specific chart behavior.

If a Stardog pod needs a specific local time zone, configure the pod according to the requirements of your Kubernetes platform. Common approaches include setting `TZ`, mounting the host time zone files, or using platform-specific settings.

For OpenShift, consult the Red Hat guidance for setting a time zone in pods. For generic Kubernetes, validate the approach against your base image and cluster policy before applying it to production.

## Validation

After changing the deployment, check the pod environment and time output:

```bash
kubectl exec -n <namespace> <pod-name> -- printenv TZ
kubectl exec -n <namespace> <pod-name> -- date
```

# `kubectl` quick reference guide

This guide will help you install `kubectl`, configure your cluster connection, and perform common operations to manage and troubleshoot your Kubernetes resources. For more information on any of the `kubectl` commands below, see the [official documentation](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands). See [here](https://kubernetes.io/docs/reference/kubectl/quick-reference/) for the official `kubectl` quick reference guide.

## Prerequisites

- `kubectl` installed: Follow the official installation instructions for your OS: https://kubernetes.io/docs/tasks/tools/
- Cluster access via `kubeconfig`: A `kubeconfig` file tells `kubectl` how to connect to your cluster (server address, credentials, and context). By default it lives at `~/.kube/config` or can be specified by the `KUBECONFIG` environment variable.
    - Azure AKS: run `az aks get-credentials --resource-group <RG> --name <clusterName>` to merge credentials.
    - AWS EKS: use `aws eks update-kubeconfig --name <clusterName>`.
    - GCP GKE: use `gcloud container clusters get-credentials <clusterName> --zone <zone>`.
    - Other clouds or on-prem: check your provider’s CLI or dashboard for instructions to generate or download the `kubeconfig`.
- Permissions and RBAC: Your Kubernetes user must have the correct Role-Based Access Control (RBAC) permissions to perform operations:
    - Check your permissions with:
    ```shell
    kubectl auth can-i get pods --all-namespaces
    kubectl auth can-i create deployment -n <namespace>
    ```
    - Azure AKS: ensure your Entra ID user or service principal is assigned roles such as `Azure Kubernetes Service Cluster Admin Role` or has the necessary Kubernetes `ClusterRoleBinding`.
    - Other clouds: verify IAM or RBAC settings in your cloud dashboard (e.g., GKE IAM roles or AWS IAM permissions mapped via the aws-auth ConfigMap).

## 1. Configuration and Context

A **context** in your `kubeconfig` defines the combination of cluster, user, and namespace that `kubectl` operates against. Switching contexts lets you quickly target different clusters or namespaces without modifying your config.
- View current context
```shell
kubectl config current-context
```
- List all contexts
```shell
kubectl config get-contexts
```
- Switch context
```shell
kubectl config use-context <context-name>
```

## 2. Viewing Resources

Use these commands to list and inspect your cluster’s resources, such as pods, services, and deployments.
- List all namespaces
```shell
kubectl get namespaces
```
- List resources in a namespace
```shell
kubectl get pods,svc,deploy -n <namespace>
```
- Describe a resource
```shell
kubectl describe <resource-type> <resource-name> -n <namespace>
```
- View resource YAML
```shell
kubectl get <resource-type> <name> -n <namespace> -o yaml
```

## 3. Creating and Applying Manifests

Kubernetes manifests are YAML files that describe the desired state of one or more resources (e.g., Pods, Services, Deployments) in your cluster. Using these commands, you can apply, update, and delete those manifest files to create or modify resources.
- Apply a manifest file
```shell
kubectl apply -f path/to/manifest.yaml
```
- Apply all files in a directory
```shell
kubectl apply -f ./k8s-manifests/
```
- Delete a resource
```shell
kubectl delete -f path/to/manifest.yaml
```
- Dry-run (preview changes)
```shell
kubectl apply -f manifest.yaml --dry-run=client
```

Note: while the above commands are all valid, changes to deployments are typically made by changes `values.yaml` and running `helm upgrade`. You can see more about editing `values.yaml` [here](./values-yaml-guide). You can learn more about `helm` in our [`helm-quick-reference-guide`](./helm-quick-reference-guide.md).

## 4. Troubleshooting and Logs

Use these commands to diagnose issues by checking logs, events, and interacting with running pods.
- View logs for a pod
```shell
kubectl logs <pod-name> -n <namespace>
```
- Follow logs in real-time
```shell
kubectl logs <pod-name> -n <namespace> -f
```
- Get events
```shell
kubectl get events -n <namespace> --sort-by='.metadata.creationTimestamp'
```
- Exec into a running pod
```shell
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
```

## 5. Scaling and Rolling Updates

These commands help you adjust replica counts and manage rolling restarts for deployments.
- Scale a deployment
```shell
kubectl scale deployment <deploy-name> --replicas=<count> -n <namespace>
```
- Trigger a rolling restart
```shell
kubectl rollout restart deployment <deploy-name> -n <namespace>
```
- Check rollout status
```shell
kubectl rollout status deployment <deploy-name> -n <namespace>
```

## 6. Port Forwarding and Access

Use port forwarding to access pods or services locally for debugging or temporary access.
- Port-forward a pod
```shell
kubectl port-forward pod/<pod-name> 8080:80 -n <namespace>
```
- Port-forward a service
```shell
kubectl port-forward svc/<service-name> 8080:80 -n <namespace>
```

## 7. Resource Usage

These commands show real-time CPU and memory usage for nodes and pods (requires [`metrics-server`](https://github.com/kubernetes-sigs/metrics-server)).
- View resource usage (`metrics-server` required)
```shell
kubectl top nodes
kubectl top pods -n <namespace>
```

## 8. Cleanup and Maintenance

Use this command to remove pods to keep your cluster tidy. Note that deleted pods will automatically be recreated. This can be useful though, because deleting a pod that gets stuck is the easiest way to restart it. Also, pods will occasionally get stuck in the `Termination` phase when you are trying to scale your cluster down, and deleting them can get them unstuck.
- Delete pods
```shell
kubectl delete pod -n <namespace>
```

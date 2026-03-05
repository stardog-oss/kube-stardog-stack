# `helm` quick reference guide

This guide will help you install [Helm](https://helm.sh/), manage chart repositories, deploy applications, and perform common maintenance and troubleshooting tasks. See [here](https://helm.sh/docs/intro/cheatsheet/) for the official Helm cheat sheet.

## Prerequisites
- Helm installed: Follow the official installation instructions for your OS: https://helm.sh/docs/intro/install/
- Cluster access via `kubeconfig`: Helm uses the same `kubeconfig` as `kubectl`, so ensure you can connect and have permissions.

## 1. Repository Management

Manage Helm chart repositories where you store and discover charts. In the coures of installing the Stardog Helm charts, we will use other charts like `nginx` and `cert-manager`.

Add a repository
```shell
helm repo add <name> <url>
```
List repositories
```shell
helm repo list
```
Update local cache
```shell
helm repo update
```

## 2. Installing Charts

Deploy applications by installing charts into your cluster.

Install a chart
```shell
helm install <release-name> <repo/chart> --namespace <ns>
```
Specify values file
```shell
helm install <release> <chart> -f values.yaml
```
Install or upgrade if already installed
```shell
helm upgrade --install <rel> <chart>
```
Dry-run install
```shell
helm install --dry-run --debug <rel> <chart>
```
## 3. Upgrading & Rolling Back

Manage application upgrades and rollbacks.

Upgrade a release
```shell
helm upgrade <release> <chart> -f values.yaml
```
Rollback to previous revision
```shell
helm rollback <release> [<revision>]
```
Get history
```shell
helm history <release>
```
## 4. Inspecting Releases

Check the status and details of deployed releases.

List releases
```shell
helm list --namespace <ns>
```
Get release status
```shell
helm status <release> --namespace <ns>
```
View manifest
```shell
helm get manifest <release>
```
Get values used
```shell
helm get values <release>
```
## 5. Uninstalling Charts

Remove applications and clean up resources.

Uninstall a release
```shell
helm uninstall <release> --namespace <ns>
```
Purge all hooks
```shell
helm uninstall <release> --namespace <ns> --keep-history
```


# ZooKeeper Chart Tests

This directory contains unit tests for the ZooKeeper Helm chart using the [helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin.

## Test Files

- **`statefulset_test.yaml`** - Tests for the ZooKeeper StatefulSet including image configuration, replicas, ports, security contexts, volumes, probes, and resource limits
- **`service_test.yaml`** - Tests for both the main Service and headless Service resources
- **`configmap_test.yaml`** - Tests for optional ConfigMap creation with custom zoo.cfg and logback.xml
- **`serviceaccount_test.yaml`** - Tests for ServiceAccount creation and configuration
- **`pdb_test.yaml`** - Tests for PodDisruptionBudget configuration
- **`rbac_test.yaml`** - Tests for RBAC Role and RoleBinding resources
- **`networkpolicy_test.yaml`** - Tests for NetworkPolicy ingress and egress rules
- **`servicemonitor_test.yaml`** - Tests for Prometheus ServiceMonitor integration
- **`ensemble_validation_test.yaml`** - Tests for ZooKeeper ensemble configuration including standalone/cluster modes, server IDs, and ZooKeeper-specific settings
- **`integration_test.yaml`** - Tests for chart-wide integration including labels, annotations, affinity, and extra configurations

## Prerequisites

Install the helm-unittest plugin:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
```

## Running Tests

### Run all tests for the ZooKeeper chart

```bash
helm unittest charts/zookeeper
```

### Run a specific test file

```bash
helm unittest -f tests/statefulset_test.yaml charts/zookeeper
```

### Run tests with verbose output

```bash
helm unittest -v charts/zookeeper
```

### Run tests with color output

```bash
helm unittest --color charts/zookeeper
```

### Update snapshots (if using snapshot testing)

```bash
helm unittest -u charts/zookeeper
```

## Test Coverage

The test suite covers:

### Core Resources
- ✅ StatefulSet with various configurations
- ✅ Service (ClusterIP, LoadBalancer, NodePort)
- ✅ Headless Service for ensemble coordination
- ✅ ConfigMap for custom configuration files
- ✅ ServiceAccount with annotations and RBAC

### Optional Resources
- ✅ PodDisruptionBudget for high availability
- ✅ RBAC (Role and RoleBinding)
- ✅ NetworkPolicy for network isolation
- ✅ ServiceMonitor for Prometheus integration

### ZooKeeper-Specific Features
- ✅ Standalone mode (single replica)
- ✅ Ensemble mode (multi-replica cluster)
- ✅ Server ID configuration with custom minServerId
- ✅ ZooKeeper configuration parameters (tickTime, initLimit, syncLimit, etc.)
- ✅ Autopurge settings
- ✅ Four letter words whitelist
- ✅ Custom cluster domain support

### Configuration Options
- ✅ Image configuration and pull secrets
- ✅ Persistent volume claims and storage classes
- ✅ EmptyDir volumes for non-persistent deployments
- ✅ Security contexts (pod and container level)
- ✅ Resource limits and requests
- ✅ Probes (readiness and liveness)
- ✅ Update strategies
- ✅ Volume permissions init container

### Kubernetes Features
- ✅ Pod and node affinity/anti-affinity
- ✅ Node selectors
- ✅ Tolerations
- ✅ Topology spread constraints
- ✅ Custom labels and annotations
- ✅ Extra environment variables, volumes, and init containers

## Test Values

The `values/values-zookeeper.yaml` file contains a base configuration used across tests. Individual tests may override specific values using the `set:` directive.

## Writing New Tests

When adding new templates or features to the ZooKeeper chart, follow these guidelines:

1. **Create tests for new templates** - Each new template should have a corresponding test file
2. **Test default behavior** - Ensure default values work as expected
3. **Test configuration options** - Verify all configurable options
4. **Test edge cases** - Include tests for boundary conditions and special scenarios
5. **Use descriptive test names** - Make it clear what each test validates
6. **Follow existing patterns** - Maintain consistency with existing test files

### Example Test Structure

```yaml
suite: Validate MyNewResource
values:
  - values/values-zookeeper.yaml
templates:
  - mynewresource.yaml

tests:
  - it: should create resource when enabled
    set:
      myNewResource.enabled: true
    asserts:
      - isKind:
          of: MyResourceKind
      - equal:
          path: metadata.name
          value: zookeeper-RELEASE-NAME
```

## Continuous Integration

These tests should be run as part of the CI/CD pipeline before merging changes to ensure:
- No regressions are introduced
- New features work as expected
- Configuration options are properly validated

## Troubleshooting

### Test failures after template changes
If tests fail after modifying templates, check:
1. The `oldString` in assertions matches the new template output
2. Required values are set in the test configuration
3. Label and selector changes are reflected in tests

### Missing assertions
If a test doesn't catch a bug:
1. Add more specific assertions for the failing case
2. Consider edge cases that weren't originally tested
3. Update the test to match the expected behavior

## References

- [helm-unittest Documentation](https://github.com/helm-unittest/helm-unittest/blob/main/DOCUMENT.md)
- [ZooKeeper Chart Values](../values.yaml)
- [ZooKeeper Official Documentation](https://zookeeper.apache.org/)

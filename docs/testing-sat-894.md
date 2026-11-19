# Testing SAT-894

Run commands from the repository root. Automated checks require Bash, Python 3,
Helm, and helm-unittest **1.0.3**, the version pinned in CI. No cluster is needed
for the automated checks. Older helm-unittest versions can fail the umbrella
suite because they cannot select its subchart templates.

## Automated checks

```bash
helm dependency build charts/stardog
helm dependency build charts/cachetarget
helm dependency build .

helm unittest --strict charts/stardog charts/cachetarget
helm unittest --strict --with-subchart=false .

bash charts/stardog/tests/scripts/secret_helpers_test.sh
bash charts/cachetarget/tests/scripts/secret_helpers_test.sh
bash charts/stardog/tests/scripts/replica_cluster_test.sh

helm lint charts/stardog -f values.skip-secret-validation.yaml
helm lint charts/cachetarget -f values.skip-secret-validation.yaml
helm lint . -f values.skip-secret-validation.yaml
git diff --check
```

All checks must pass. The helper tests execute the actual shell function bodies
with mocked external commands and sentinel passwords containing spaces and shell
metacharacters. They check authentication arguments, error propagation, retries,
and absence of credentials from stdout and stderr. The Helm tests cover hook
configuration, outbound-only trust, JWT false/default values, and replica behavior.
These checks do not verify the CLI against a running Stardog server.

## Live Stardog check

Use a disposable namespace and your working **standalone Stardog chart** values
file, called `local-values.yaml` below. It must supply an accessible image and
storage configuration. Create the required `stardog-license` Secret in namespace
`sat894` before installation. Keep replica mode disabled for this test.

1. Create two test-only Secrets in that namespace: `sat894-admin`, with a
   `password` key, and `sat894-backup`, with `username` and `password` keys.
   Use distinct non-default passwords. Include spaces and shell metacharacters
   to exercise argument quoting.
2. Create `/tmp/sat894-values.yaml`:

   ```yaml
   cluster:
     enabled: false
   replicaCluster:
     enabled: false
   admin:
     existingSecretName: sat894-admin
     existingSecretKey: password
   backup:
     enabled: true
     credentialsSecret: sat894-backup
     cronjob:
       enabled: false
   ```

3. Install the chart:

   ```bash
   helm install sat894 charts/stardog -n sat894 \
     -f local-values.yaml -f /tmp/sat894-values.yaml \
     --wait --timeout 15m
   ```

   Installation must succeed. Using the configured admin credentials through
   your usual client, verify that the backup user exists, belongs to `backup`,
   and has `execute` permission on `dbms-admin:backup-all`.

4. Re-run the hook as an ordinary Job to retain its logs for inspection.
   Helm normally deletes a successful hook Job. Wait for that deletion before
   applying this rendered Job:

   ```bash
   helm template sat894 charts/stardog -n sat894 \
     -f local-values.yaml -f /tmp/sat894-values.yaml \
     --set global.skipSecretValidation=true \
     --show-only templates/job-post-install.yaml \
     | kubectl apply -f -
   kubectl wait -n sat894 --for=condition=complete \
     job/stardog-sat894 --timeout=15m
   kubectl logs -n sat894 job/stardog-sat894
   ```

   This repeats setup after the admin password has changed and the backup user
   already exists. The Job must succeed. Neither test password may appear in
   the logs. Retain the Job until log inspection is complete.

5. For the failure path, replace the test admin Secret's password with an
   incorrect value, delete only the retained test Job, and repeat step 4.
   The Job must fail rather than report successful provisioning. Restore the
   correct Secret value afterward.

## Outbound trust, registry, and CacheTarget checks

- Create a Secret containing your private CA certificate and set
  `tls.truststore.enabled=true` and `tls.truststore.caSecretName` to its name.
  Leave `tls.sparql.enabled=false` and `tls.bi.enabled=false`. Upgrade the test
  release. Confirm the keystore directory is mounted in both init and main
  containers, the generated truststore contains the CA, and
  `STARDOG_SERVER_JAVA_ARGS` includes `-Djavax.net.ssl.trustStore` without
  `-Djavax.net.ssl.keyStore`. Exercise an actual Stardog outbound HTTPS request
  to a service signed by that CA; verify trust succeeds without disabling
  certificate validation.
- With a working registry Secret, set `image.pullSecrets` and inspect the hook
  Job's **pod spec**. Test on a node without the image cached to confirm the
  registry credentials actually allow the image to pull. Test `clusterDomain`
  using the real domain of your test cluster, not an arbitrary hostname.
- Deploy CacheTarget against the test primary using your existing working
  CacheTarget values and the matching primary/cache password Secrets. Capture
  the post-install Job logs while it runs, or render and apply its hook as an
  ordinary retained Job as above. Confirm registration succeeds without either
  password in the logs; repeat registration to exercise the already-registered
  path. Use invalid primary credentials to confirm registration fails.

Remove the disposable release, retained Jobs, namespace, and local test files
when finished.

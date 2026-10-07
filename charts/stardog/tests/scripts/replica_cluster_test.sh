#!/usr/bin/env bash
# Script-level tests for replica cluster behaviour that helm-unittest cannot express:
#   - pod rollout checksums change when replica settings or credentials change (needs two renders)
#   - the rendered credential block, executed under `bash -ex`, escapes values for
#     java.util.Properties, rejects unsafe values and never traces a secret
# Requires bash, helm and awk; the java.util.Properties round trip runs when `java` (11+) is available.
# Usage: bash charts/stardog/tests/scripts/replica_cluster_test.sh
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1" >&2; }
check() { local name="$1"; shift; if "$@"; then pass "${name}"; else fail "${name}"; fi; }

BASE_ARGS=(
  --set global.skipSecretValidation=true
  --set image.tag=12.2.0
  --set cluster.enabled=true
  --set cluster.zookeeperService=zk:2181
  --set replicaCluster.enabled=true
  --set replicaCluster.primary.address=sparql.dc1.example.com:443
)
SECRET_ARGS=(--set replicaCluster.primary.credentials.existingSecretName=primary-replication)

render_statefulset() {
  helm template t "${CHART_DIR}" -s templates/statefulset.yaml "${BASE_ARGS[@]}" "$@"
}

annotation() {
  # annotation <name> <helm args...>
  local name="$1"; shift
  render_statefulset "$@" | awk -v k="checksum/${name}:" '$1 == k {print $2; exit}'
}

# ------------------------------------------------------------------ rollout checksums
echo "Rollout checksums"

base_config="$(annotation config "${SECRET_ARGS[@]}")"
base_secret="$(annotation secret "${SECRET_ARGS[@]}")"
check "checksum/config is present" test -n "${base_config}"
check "checksum/secret is present" test -n "${base_secret}"
check "checksums are stable across identical renders" \
  test "$(annotation config "${SECRET_ARGS[@]}")$(annotation secret "${SECRET_ARGS[@]}")" = "${base_config}${base_secret}"
check "checksum/config changes with replicaCluster.syncInterval" \
  test "$(annotation config "${SECRET_ARGS[@]}" --set replicaCluster.syncInterval=2m)" != "${base_config}"
check "checksum/config changes with replicaCluster.primary.address" \
  test "$(annotation config "${SECRET_ARGS[@]}" --set replicaCluster.primary.address=other.example.com:443)" != "${base_config}"
check "checksum/config changes when replica mode is turned off (promotion upgrade)" \
  test "$(annotation config --set replicaCluster.enabled=false)" != "${base_config}"
check "checksum/secret changes with replicaCluster.restartToken" \
  test "$(annotation secret "${SECRET_ARGS[@]}" --set replicaCluster.restartToken=rotated)" != "${base_secret}"
check "checksum/secret changes with the credentials Secret name" \
  test "$(annotation secret --set replicaCluster.primary.credentials.existingSecretName=other)" != "${base_secret}"
check "checksum/secret ignores the restart token when replica mode is off" \
  test "$(annotation secret --set replicaCluster.enabled=false --set replicaCluster.restartToken=a)" = \
       "$(annotation secret --set replicaCluster.enabled=false --set replicaCluster.restartToken=b)"

# ------------------------------------------------------------------ credential script
echo "Credential script"

CRED_DIR="${WORK}/cred"
mkdir -p "${CRED_DIR}"

# extract_block <file> <helm args...>: the rendered credential block, with credential paths
# pointed at CRED_DIR.
extract_block() {
  local out="$1"; shift
  render_statefulset "$@" \
    | awk '/# Append the primary.s credentials/ {on=1} on {print} on && /^[[:space:]]*set -x[[:space:]]*$/ {exit}' \
    | sed -e 's/^          //' -e "s#/etc/stardog-replica#${CRED_DIR}#g" > "${out}"
  [[ -s "${out}" ]]
}

# run_block <block> : runs the block like the container does (set -ex), into PROPS
run_block() {
  PROPS="${WORK}/stardog.properties"
  : > "${PROPS}"
  STARDOG_PROPERTIES="${PROPS}" bash -c "set -ex; source '$1'" > "${WORK}/stdout" 2> "${WORK}/stderr"
}

SECRET_BLOCK="${WORK}/secret-block.sh"
LITERAL_BLOCK="${WORK}/literal-block.sh"
check "credential block renders (Secret mode)" extract_block "${SECRET_BLOCK}" "${SECRET_ARGS[@]}"
check "credential block renders (literal username + passwordFile)" extract_block "${LITERAL_BLOCK}" \
  --set replicaCluster.primary.credentials.username=replicator \
  --set replicaCluster.primary.credentials.passwordFile=/etc/stardog-replica/password

PASSWORD=' p\a=ss:#!x'
printf 'repl user' > "${CRED_DIR}/username"
printf '%s\n' "${PASSWORD}" > "${CRED_DIR}/password"   # trailing newline, as kubectl --from-file often leaves
if run_block "${SECRET_BLOCK}"; then pass "valid credentials are appended"; else fail "valid credentials are appended"; cat "${WORK}/stderr" >&2; fi
check "username line is written" grep -qxF 'pack.replicaCluster.primary.user=repl user' "${PROPS}"
check "password is escaped for java.util.Properties" \
  grep -qxF 'pack.replicaCluster.primary.password=\ p\\a=ss:#!x' "${PROPS}"
check "trailing newline in the credential file is dropped" test "$(wc -l < "${PROPS}" | tr -d ' ')" = 2
check "neither credential reaches the shell trace" \
  bash -c "! grep -qF 'repl user' '${WORK}/stderr' && ! grep -qF 'ss:#!x' '${WORK}/stderr'"
check "tracing is turned back on after the block" bash -c "grep -q 'set -x\$' '${SECRET_BLOCK}'"

if command -v java > /dev/null 2>&1; then
  cat > "${WORK}/ReadProps.java" <<'JAVA'
import java.io.FileInputStream;
import java.util.Properties;
public class ReadProps {
    public static void main(String[] args) throws Exception {
        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream(args[0])) { p.load(in); }
        System.out.print(p.getProperty("pack.replicaCluster.primary.user") + "\n" + p.getProperty("pack.replicaCluster.primary.password"));
    }
}
JAVA
  check "java.util.Properties reads back the exact credentials" \
    test "$(java "${WORK}/ReadProps.java" "${PROPS}")" = "repl user"$'\n'"${PASSWORD}"
else
  echo "  SKIP  java.util.Properties round trip (java not found)"
fi

# A literal username is rendered into the ConfigMap by the template, not by the script; it must get
# the same escaping. Values file, not --set: --set treats backslashes as escapes itself.
LITERAL_USER='ACME\replicator'
printf 'replicaCluster:\n  primary:\n    credentials:\n      username: %s\n' "'${LITERAL_USER}'" > "${WORK}/literal-user.yaml"
helm template t "${CHART_DIR}" -s templates/configmap.yaml "${BASE_ARGS[@]}" \
  --set replicaCluster.primary.credentials.passwordFile=/etc/stardog-replica/password -f "${WORK}/literal-user.yaml" \
  | awk '/^    pack\.replicaCluster\.primary\.user=/ {sub(/^    /, ""); print}' > "${WORK}/literal-user.properties"
check "literal username line renders" grep -q '^pack.replicaCluster.primary.user=' "${WORK}/literal-user.properties"
if command -v java > /dev/null 2>&1; then
  check "java.util.Properties reads back the exact literal username" \
    test "$(java "${WORK}/ReadProps.java" "${WORK}/literal-user.properties" | head -1)" = "${LITERAL_USER}"
fi

printf 'line1\nline2' > "${CRED_DIR}/password"
check "a password with an embedded newline is rejected" bash -c "! STARDOG_PROPERTIES='${WORK}/p' bash -c 'set -e; source \"${SECRET_BLOCK}\"' 2> '${WORK}/stderr'"
check "the newline error names the file, not the value" bash -c "grep -q 'contains a newline' '${WORK}/stderr' && ! grep -q line1 '${WORK}/stderr'"

printf 'w\xc3\xb6rd' > "${CRED_DIR}/password"
check "a non-ASCII password is rejected" bash -c "! STARDOG_PROPERTIES='${WORK}/p' bash -c 'set -e; source \"${SECRET_BLOCK}\"' 2> '${WORK}/stderr'"
check "the non-ASCII error is reported" grep -q 'non-printable or non-ASCII' "${WORK}/stderr"

rm -f "${CRED_DIR}/password"
check "a missing credential file fails the start" bash -c "! STARDOG_PROPERTIES='${WORK}/p' bash -c 'set -e; source \"${SECRET_BLOCK}\"' 2> /dev/null"

printf 'secret' > "${CRED_DIR}/password"
run_block "${LITERAL_BLOCK}"
check "literal username mode appends only the password" \
  bash -c "grep -qxF 'pack.replicaCluster.primary.password=secret' '${PROPS}' && ! grep -q 'primary.user' '${PROPS}'"

echo
echo "Replica cluster script tests: ${PASSED} passed, ${FAILED} failed"
[[ "${FAILED}" -eq 0 ]]

#!/usr/bin/env bash
# Execute real helper bodies with mocked external commands under inherited xtrace.
set -euo pipefail
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$CHART_DIR" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

chart = Path(sys.argv[1])
admin_secret = 'ADMIN_SENTINEL space * $quote'
backup_secret = 'BACKUP_SENTINEL space * $quote'
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    log = work / 'commands.jsonl'
    mock = work / 'stardog-admin'
    mock.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['COMMAND_LOG'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
operation = ' '.join(args[2:4])
if operation == os.environ.get('FAIL_OPERATION'):
    sys.exit(17)
if operation in ('role permission', 'user permission'):
    sys.exit(0 if os.environ.get('EXISTING') == 'true' else 1)
''')
    mock.chmod(0o755)
    source = work / 'utils.sh'
    source.write_text((chart / 'files/utils.sh').read_text().replace('/opt/stardog/bin/stardog-admin', str(mock)))
    env = dict(os.environ, COMMAND_LOG=str(log), ADMIN_SECRET=admin_secret, BACKUP_SECRET=backup_secret)

    def run(body, failure='', existing=False, expected=0):
        log.write_text('')
        script = f'''source "{source}"
cat() {{ printf '%s' "$ADMIN_SECRET"; }}
curl() {{ printf '%s\\n' 'mock HTTP response'; return "${{CURL_STATUS:-0}}"; }}
set -ex
{body}
'''
        result = subprocess.run(['bash', '-c', script], env=dict(env, FAIL_OPERATION=failure, EXISTING=str(existing).lower()), capture_output=True, text=True)
        assert result.returncode == expected, (body, result.returncode, result.stdout, result.stderr)
        for secret in (admin_secret, backup_secret):
            assert secret not in result.stdout + result.stderr, 'credential leaked into logs'
        return [json.loads(line) for line in log.read_text().splitlines()]

    for function in ('change_pw', 'add_roles'):
        for failure in ('', 'user passwd'):
            calls = run(f'{function} host 5820 http role', failure)
            assert calls[0][-1] == admin_secret, 'password split or globbed'
    body = '''{ set +x; } 2>/dev/null
backup_credentials http://host:5820 'backup user' "$BACKUP_SECRET"'''
    for existing in (False, True):
        calls = run(body, existing=existing)
        for args in calls:
            assert args[args.index('-u') + 1] == 'admin'
            assert args[args.index('-p') + 1] == admin_secret
        operations = [' '.join(args[2:4]) for args in calls]
        assert 'role grant' in operations and 'user addrole' in operations
        assert ('user add' in operations) != existing
        if not existing:
            args = calls[operations.index('user add')]
            assert args[args.index('-N') + 1] == backup_secret
            assert args[-2:] == ['--', 'backup user']
    for operation in ('role add', 'role grant', 'user add', 'user addrole'):
        calls = run(body, operation, expected=17)
        assert ' '.join(calls[-1][2:4]) == operation, 'continued after provisioning failed'
    print('PASS: password change, fallback, backup authentication, retries, failure propagation and log secrecy')
    # The init script must also keep store passwords out of stdout, with no real key tooling.
    tls_source = work / 'tls.sh'
    tls_source.write_text((chart / 'files/pre-hook-script.sh').read_text().replace('/var/opt/stardog', str(work / 'tls')))
    script = f'''source "{tls_source}"
keytool() {{ return 0; }}
openssl() {{ return 0; }}
findDefaultCacerts() {{ printf '%s' '/mock/cacerts'; }}
set -ex
{{ set +x; }} 2>/dev/null
generateKeystore store.p12 "$ADMIN_SECRET"
generateTruststore trust.p12 "$ADMIN_SECRET" "$BACKUP_SECRET"
generateCertificates store.p12 "$ADMIN_SECRET"
'''
    result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    for secret in (admin_secret, backup_secret):
        assert secret not in result.stdout + result.stderr, 'TLS store credential leaked into logs'
    print('PASS: TLS keystore, truststore and certificate helpers keep credentials out of logs')
PY

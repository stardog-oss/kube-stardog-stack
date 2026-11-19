#!/usr/bin/env bash
set -euo pipefail
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$CHART_DIR" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

chart = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'utils.sh'
    source.write_text((chart / 'files/utils.sh').read_text().replace('/opt/stardog/bin/stardog-admin', 'mock_admin'))
    env = dict(os.environ, STARDOG_ADMINPW='CACHE_SENTINEL space *', PRIMARY_PW='PRIMARY_SENTINEL space *')
    for mode, status in [('success', 0), ('existing', 0), ('failure', 1)]:
        script = f'''source "{source}"
mock_admin() {{
  if [[ "$*" == *'user passwd'* ]]; then
    [[ "${{@: -1}}" == "$STARDOG_ADMINPW" ]] || exit 90
    return 1
  fi
  [[ "${{@: -1}}" == "$STARDOG_ADMINPW" ]] || exit 91
  [[ "$4" == target && "$7" == "$PRIMARY_PW" ]] || exit 92
  case "$MODE" in
    existing) echo 'already registered'; return 1;;
    failure) echo 'mock registration failure'; return 1;;
  esac
}}
curl() {{ [[ "$3" == "admin:$STARDOG_ADMINPW" ]] || exit 93; }}
set -ex
change_pw cache 5820
setup_cache_target target 5820 primary 5820 namespace
'''
        result = subprocess.run(['bash', '-c', script], env=dict(env, MODE=mode), capture_output=True, text=True)
        assert result.returncode == status, (mode, result.returncode, result.stdout, result.stderr)
        for secret in (env['STARDOG_ADMINPW'], env['PRIMARY_PW']):
            assert secret not in result.stdout + result.stderr, 'credential leaked into logs'
    print('PASS: cache password fallback and registration success, already-registered and failure paths keep credentials literal and out of logs')
PY

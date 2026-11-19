#!/usr/bin/env bash
# Exercise Helm's actual NOTES output and the packaged standalone/umbrella charts.
# Requires Helm and Python 3; build chart dependencies before running.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The umbrella CI job builds only root dependencies. Its standalone source chart
# needs its own common archive, independently of the umbrella's packaged copy.
helm dependency build "$REPO_ROOT/charts/cachetarget" --skip-refresh >/dev/null
python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

root = Path(sys.argv[1])
cache = root / 'charts/cachetarget'
offline = ['-f', str(root / 'values.skip-secret-validation.yaml')]
notice = 'WARNING: The CacheTarget chart is deprecated.'
checks = 0

def check(args, blocked=False, notes=False, quiet=False):
    global checks
    result = subprocess.run(['helm', *map(str, args)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if blocked:
        assert result.returncode != 0, 'unacknowledged deployment was accepted'
        assert notice in output and 'cachetarget.allowDeprecated=true' in output, output
        assert not result.stdout.strip(), 'failed render emitted resources'
    else:
        assert result.returncode == 0, output
    if notes:
        assert 'NOTES:' in result.stdout, 'install output omitted NOTES'
        assert notice in result.stdout.split('NOTES:', 1)[1], 'deprecation warning missing from visible NOTES'
    if quiet:
        assert notice not in output, 'disabled CacheTarget produced a deprecation warning'
        assert 'kind: StatefulSet\nmetadata:\n  name: cachetarget-' not in result.stdout
    checks += 1

with tempfile.TemporaryDirectory(prefix='sat905-') as directory:
    work = Path(directory)
    check(['install', 'sat905', cache, '--dry-run=client', *offline], blocked=True)
    check(['template', 'sat905', cache, *offline, '--set-string', 'allowDeprecated=true'], blocked=True)
    check(['install', 'sat905', cache, '--dry-run=client', *offline, '--set', 'allowDeprecated=true'], notes=True)
    # Subchart NOTES are hidden by Helm by default. The umbrella must show its own warning.
    check(['install', 'sat905', root, '--dry-run=client', *offline], quiet=True)
    check(['install', 'sat905', root, '--dry-run=client', *offline,
           '--set', 'global.cachetarget.enabled=true,cachetarget.allowDeprecated=true'], notes=True)

    for chart, relative in [(cache, 'cachetarget'), (root, 'kube-stardog-stack')]:
        check(['package', chart, '--destination', work])
        archive = next(work.glob(f'{relative}-*.tgz'))
        with tarfile.open(archive) as package:
            metadata = package.extractfile(f'{relative}/Chart.yaml').read().decode()
            if relative == 'cachetarget':
                assert re.search(r'^deprecated: true$', metadata, re.M), 'chart metadata is not deprecated'
            else:
                assert not re.search(r'^deprecated: true$', metadata, re.M), 'umbrella was marked deprecated'

        flags = (['--set', 'allowDeprecated=true'] if relative == 'cachetarget'
                 else ['--set', 'global.cachetarget.enabled=true,cachetarget.allowDeprecated=true'])
        enabled = ([] if relative == 'cachetarget' else ['--set', 'global.cachetarget.enabled=true'])
        check(['template', 'sat905', archive, *offline, *enabled], blocked=True)
        check(['template', 'sat905', archive, '--is-upgrade', *offline, *enabled], blocked=True)
        check(['template', 'sat905', archive, '--is-upgrade', *offline, *flags])
        check(['install', 'sat905', archive, '--dry-run=client', *offline, *flags], notes=True)
        if relative != 'cachetarget':
            check(['install', 'sat905', archive, '--dry-run=client', *offline,
                   '--set', 'cachetarget.allowDeprecated=true'], quiet=True)

print(f'CacheTarget deprecation CLI/package checks: {checks} passed')
PY

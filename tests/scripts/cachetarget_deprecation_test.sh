#!/usr/bin/env bash
# Exercise rendered NOTES and packaged standalone/umbrella charts without a cluster.
# Requires Helm and Python 3; build root dependencies before running.
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

def check(args, blocked=False, quiet=False):
    global checks
    result = subprocess.run(['helm', *map(str, args)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if blocked:
        assert result.returncode != 0, 'unacknowledged deployment was accepted'
        if isinstance(blocked, str):
            assert blocked in output, output
        else:
            assert notice in output and 'cachetarget.allowDeprecated=true' in output, output
        assert 'https://docs.stardog.com/high-availability-cluster/operating-the-cluster/cache-management' in output, output
        assert not result.stdout.strip(), 'failed render emitted resources'
    else:
        assert result.returncode == 0, output
    if quiet:
        assert notice not in output, 'disabled CacheTarget produced a deprecation warning'
        assert 'kind: StatefulSet\nmetadata:\n  name: cachetarget-' not in result.stdout
    checks += 1
    return result.stdout

with tempfile.TemporaryDirectory(prefix='sat905-') as directory:
    work = Path(directory)
    check(['template', 'sat905', cache, *offline], blocked=True)
    check(['template', 'sat905', cache, *offline, '--set-string', 'allowDeprecated=true'], blocked=True)

    for chart, relative in [(cache, 'cachetarget'), (root, 'kube-stardog-stack')]:
        check(['package', chart, '--destination', work])
        archive = next(work.glob(f'{relative}-*.tgz'))
        with tarfile.open(archive) as package:
            metadata = package.extractfile(f'{relative}/Chart.yaml').read().decode()
            if relative == 'cachetarget':
                assert re.search(r'^deprecated: true$', metadata, re.M), 'chart metadata is not deprecated'
            else:
                assert not re.search(r'^deprecated: true$', metadata, re.M), 'umbrella was marked deprecated'
            # This archive was generated above from the local chart, not downloaded.
            package.extractall(work / 'notes')

        flags = (['--set', 'allowDeprecated=true,image.tag=12.2.0,primary.version=12.2.0'] if relative == 'cachetarget'
                 else ['--set', 'global.cachetarget.enabled=true,cachetarget.allowDeprecated=true,cachetarget.image.tag=12.2.0,cachetarget.primary.version=12.2.0,stardog.image.tag=12.2.0'])
        enabled = ([] if relative == 'cachetarget' else ['--set', 'global.cachetarget.enabled=true'])
        check(['template', 'sat905', archive, *offline, *enabled], blocked=True)
        check(['template', 'sat905', archive, '--is-upgrade', *offline, *enabled], blocked=True)
        check(['template', 'sat905', archive, '--is-upgrade', *offline, *flags])
        target_key = 'image.tag' if relative == 'cachetarget' else 'cachetarget.image.tag'
        primary_key = 'primary.version' if relative == 'cachetarget' else 'cachetarget.primary.version'
        for version in ('13.0.0', 'v13.0.0-rc.1', '14.0.0'):
            for upgrade in ([], ['--is-upgrade']):
                check(['template', 'sat905', archive, *upgrade, *offline, *flags,
                       '--set', f'{target_key}={version}'], blocked='Cache targets are removed in Stardog 13.')
        check(['template', 'sat905', archive, *offline, *flags, '--set', f'{primary_key}=13.0.0'],
              blocked='Cache targets are removed in Stardog 13.')
        check(['template', 'sat905', archive, *offline, *flags, '--set', f'{target_key}=latest'],
              blocked='must be an explicit Stardog version below 13')
        if relative != 'cachetarget':
            check(['template', 'sat905', archive, *offline, *flags, '--set', 'stardog.image.tag=13.0.0'],
                  blocked='Cache targets are removed in Stardog 13.')

        # Helm 3 install dry-runs still require a reachable cluster. Render the
        # actual top-level NOTES template through a temporary ConfigMap instead.
        # This also proves the umbrella warning does not depend on subchart NOTES.
        probe = work / 'notes' / relative
        (probe / 'templates/NOTES.txt').rename(probe / 'notes-under-test.txt')
        (probe / 'templates/notes-probe.yaml').write_text('''apiVersion: v1
kind: ConfigMap
metadata:
  name: notes-probe
data:
  notes: |
{{ tpl (.Files.Get "notes-under-test.txt") . | indent 4 }}
''')
        for upgrade in ([], ['--is-upgrade']):
            output = check(['template', 'sat905', probe, *upgrade, *offline, *flags,
                            '--show-only', 'templates/notes-probe.yaml'])
            assert notice in output, 'deprecation warning missing from top-level NOTES'
            assert 'removed in Stardog 13' in output and 'cache-management' in output, 'removal version or documentation link missing'
        if relative != 'cachetarget':
            check(['template', 'sat905', archive, *offline], quiet=True)
            for extra in ([], ['--set', 'cachetarget.allowDeprecated=true']):
                check(['template', 'sat905', probe, *offline, *extra,
                       '--show-only', 'templates/notes-probe.yaml'], quiet=True)

print(f'CacheTarget deprecation CLI/package checks: {checks} passed')
PY

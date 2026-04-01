# Pre-commit hook for Helm charts (two‑phase, emoji/ASCII toggle)

This merged pre-commit runs **changelog checks**, then two phases across **all charts** it finds (umbrella + subcharts):


0. **CHANGELOG** – Ensures each chart version appears in its `CHANGELOG.md`.
   Version bump enforcement no longer happens in pre-commit. It happens in the release-tag workflow when you push `vX.Y.Z`.
1. **Sync locks** – `helm dependency build` for each chart; if a lock is out of sync, it runs
   `helm dependency update` and rebuilds, then **stages the updated `Chart.lock`**.
2. **Quality checks** – `helm lint` and `helm unittest --strict .` for each chart (only after Phase 1 succeeds).
3. **Sandboxed Helm state** – the hook uses a repo-local Helm home under `.helm-hook/` so it does not depend on your global Helm repository configuration.

Charts are discovered by scanning for `**/Chart.yaml` (excluding vendored deps under `*/charts/*/charts/*`).

---

## Install (one-time per clone)

```bash
git config core.hooksPath .githooks
```

> The hook runs regardless of whether you pass `-m` or open an editor; pre-commit fires **before** the editor is shown.

---

## Emoji / ASCII output

The hook can print pretty icons (default) or plain ASCII for CI/minimal logs.

- **Enable emojis (default):** `USE_EMOJI=1`
- **Disable emojis:** `USE_EMOJI=0`

Examples:
```bash
# local with emojis
git commit -m "feat: run pre-commit with icons"

# CI or plain logs
USE_EMOJI=0 git commit -m "feat: ascii logs"
```

In GitHub Actions, set an env var before running any git commands:
```yaml
env:
  USE_EMOJI: "0"
---

## Bypass (when you must)

```bash
SKIP_HELM_HOOKS=1 git commit -m "emergency"
# or:
git commit --no-verify -m "emergency"
```

---

## Requirements

- Helm installed: <https://helm.sh/docs/intro/install/>
- `helm-unittest` plugin:
  ```bash
  helm plugin install https://github.com/helm-unittest/helm-unittest
  ```
```

---

## Run manually (no commit)

```bash
./.githooks/pre-commit
```

---

## Troubleshooting

- **“Helm not found”** – Install Helm and re-run.
- **“helm-unittest plugin missing”** – Install the plugin once:  
  `helm plugin install https://github.com/helm-unittest/helm-unittest`
- **Commit aborted after lock changes** – The hook may have **staged** updated `Chart.lock` files.  
  Keep them staged for the next commit or unstage with `git reset <chart>/Chart.lock`.
- **Garbled icons / squares** – Set `USE_EMOJI=0` for ASCII output.
- **Only some charts are checked** – The hook looks for tracked `Chart.yaml`. Ensure the charts are committed and not nested under a vendored `*/charts/*/charts/*` path.
- **Version bump was not enforced locally** – This is expected. Version bump enforcement now happens only during the final release tag workflow.
- **Many unrelated Helm repos are being updated** – This should no longer happen. The hook now uses a repo-local Helm sandbox and only adds repositories referenced by the charts.

---

## Optional: scope to specific branches

Edit `.githooks/pre-commit` and add near the top:
```bash
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ ! "$branch" =~ ^(SAT|CLOUD)-[0-9]+ ]]; then
  exit 0  # only run on feature branches
fi
```

---

## Optional: run only for changed charts

Replace the discovery loop with one that inspects the staged diff and falls back to all charts if none detected. (Ask if you want me to wire this for you.)

---

## Notes

- Phase 1 (lock sync) happens **before** lint/tests, so dependency drift won’t cause false negatives.
- The hook is Bash 3+ compatible (works on macOS default Bash and modern shells).
- You can keep a standalone copy of the script and run it directly if desired.

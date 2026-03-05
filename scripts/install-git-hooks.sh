#!/usr/bin/env bash
# One-time installer to enable repo-managed Git hooks
set -euo pipefail
git config core.hooksPath .githooks
echo "✔ Repo-managed Git hooks enabled (core.hooksPath=.githooks)"
echo "Next: ensure you have helm & helm-unittest plugin:"
echo "  - Helm: https://helm.sh/docs/intro/install/"
echo "  - Plugin: helm plugin install https://github.com/helm-unittest/helm-unittest"

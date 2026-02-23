#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n scripts/ralph-monitor.sh

if grep -n -E '/U[s]ers/[a-z]|n[o]va\b|7572400[5]69|\bB[e]n\b' scripts/ralph-monitor.sh >/dev/null; then
  echo "Found hardcoded personal data in scripts/ralph-monitor.sh" >&2
  exit 1
fi

echo "test_monitor.sh: OK"

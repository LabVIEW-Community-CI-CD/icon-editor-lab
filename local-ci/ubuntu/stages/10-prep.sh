#!/usr/bin/env bash
set -euo pipefail

: "${LOCALCI_SIGN_ROOT:?LOCALCI_SIGN_ROOT not set}"
: "${LOCALCI_RUN_ROOT:?LOCALCI_RUN_ROOT not set}"
: "${LOCALCI_REPO_ROOT:?LOCALCI_REPO_ROOT not set}"

echo "Sign root : $LOCALCI_SIGN_ROOT"
echo "Run root  : $LOCALCI_RUN_ROOT"

mkdir -p "$LOCALCI_SIGN_ROOT" "$LOCALCI_RUN_ROOT"

missing=()
if ! command -v pwsh >/dev/null 2>&1; then
  missing+=("pwsh")
fi
if ! command -v python3 >/dev/null 2>&1; then
  missing+=("python3")
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "[10-prep] zip CLI not found; packaging stage will use Python fallback." >&2
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "[10-prep] Missing required commands: ${missing[*]}" >&2
  exit 1
fi

preserve_dirs=(local-signing-logs local-ci local-ci-ubuntu)
for dir in "${preserve_dirs[@]}"; do
  mkdir -p "$LOCALCI_SIGN_ROOT/$dir"
done

git_status_file="$LOCALCI_RUN_ROOT/git-status.txt"
if command -v git >/dev/null 2>&1; then
  git -C "$LOCALCI_REPO_ROOT" status --short > "$git_status_file" || true
else
  printf 'git not found; skipped status snapshot\n' > "$git_status_file"
fi

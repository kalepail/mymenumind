#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
Scripts/package-app.sh >/dev/null

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Include untracked non-ignored files so a brand-new repo cannot pass with an
  # empty index before its first commit.
  tracked_files="$(git ls-files --cached --others --exclude-standard)"
else
  tracked_files="$(find . -type f \
    -not -path './.build/*' \
    -not -path './.claude/*' \
    -not -path './.git/*' \
    -not -path './mymind-api-docs/*' \
    -not -name '.env' \
    -not -name '.env.*' \
    -print)"
fi

blocked_artifacts_pattern='(^|/)(\.env(\.|$)|\.claude/|\.build/|mymind-api-docs/)'
if printf '%s\n' "$tracked_files" | grep -E "$blocked_artifacts_pattern" >/dev/null; then
  echo "Publish check failed: local secrets, agent state, build output, or generated docs are in the publishable file set." >&2
  printf '%s\n' "$tracked_files" | grep -E "$blocked_artifacts_pattern" >&2
  exit 1
fi

secret_pattern='(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |OPENSSH |DSA |EC |PGP )?PRIVATE KEY-----)'
scan_targets="$(printf '%s\n' "$tracked_files" | sed 's#^\./##')"

if [ -n "$scan_targets" ]; then
  scan_files=()
  while IFS= read -r file; do
    [ -f "$file" ] && scan_files+=("$file")
  done <<< "$scan_targets"

  if [ "${#scan_files[@]}" -gt 0 ] && rg --hidden --no-messages -n "$secret_pattern" "${scan_files[@]}" >/tmp/mymenumind-secret-scan.txt; then
    echo "Publish check failed: possible secret material found in publishable files." >&2
    cat /tmp/mymenumind-secret-scan.txt >&2
    exit 1
  fi
fi

echo "Release readiness check passed."

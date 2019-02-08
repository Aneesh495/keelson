#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EM_DASH=$'\xe2\x80\x94'
FOUND=0

echo "Checking for prohibited em dashes in $REPO_ROOT..."

FILES=$(git ls-files 2>/dev/null || find . -type f ! -path "*/.git/*" ! -path "*/build/*" ! -path "*/venv/*")

for file in $FILES; do
  if [ -f "$file" ]; then
    if grep -q -F "$EM_DASH" "$file" 2>/dev/null; then
      echo "ERROR: Em dash found in $file:"
      grep -n -F "$EM_DASH" "$file"
      FOUND=1
    fi
  fi
done

if [ "$FOUND" -eq 1 ]; then
  echo "Lint failed: Prohibited em dashes detected."
  exit 1
fi

echo "Clean: Zero prohibited em dashes found."
exit 0

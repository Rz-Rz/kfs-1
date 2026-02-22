#!/usr/bin/env bash
set -euo pipefail

# Prefer the subject-mandated target once it actually exists in this repo.
if [[ -d src/arch/i386 ]]; then
  if find src/arch/i386 -type f | head -n 1 | grep -q .; then
    echo "i386"
    exit 0
  fi
fi

# Current repo sources are under src/arch/x86_64/.
echo "x86_64"


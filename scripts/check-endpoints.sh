#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Usage: $0 https://app.example.com}"
for path in /health /ready /; do
  echo "== ${BASE}${path}"
  curl --fail --silent --show-error --max-time 10 "${BASE%/}${path}"
  echo
done

#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/timeweb-floating-ip-cleanup.yaml"

test -f "${workflow}"
grep -Fq 'https://api.timeweb.cloud/api/v1/floating-ips' "${workflow}"
test "$(grep -Fc '[.ips[] | . as $item |' "${workflow}")" -eq 2
grep -Fq "Account public IP count:" "${workflow}"
grep -Fq '($comments | index($item.comment)) != null' "${workflow}"
grep -Fq '($ips | index($item.ip)) != null' "${workflow}"
grep -Fq 'if: inputs.delete' "${workflow}"
grep -Fq 'Verify exact matches are absent' "${workflow}"

if grep -Eq 'contains\(|startswith\(|test\(' "${workflow}"; then
  echo "cleanup selectors must use exact matches" >&2
  exit 1
fi

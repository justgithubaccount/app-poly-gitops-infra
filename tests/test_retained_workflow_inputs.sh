#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${repo_root}/scripts/validate-retained-workflow-inputs.sh"

"${validator}" v1.5.1 1.1.2 0.1.3

for invalid_revision in main HEAD 0925bc568e8c279eff98a8093c35ad4c0c9ebc9e v1.5 v1.5.1-rc.1; do
  if "${validator}" "${invalid_revision}" 1.1.2 0.1.3; then
    echo "accepted invalid GitOps revision: ${invalid_revision}" >&2
    exit 1
  fi
done

for invalid_tag in latest main 1.1 1.1.2-rc.1 '1.1.2;echo'; do
  if "${validator}" v1.5.1 "${invalid_tag}" 0.1.3; then
    echo "accepted invalid FastAPI image tag: ${invalid_tag}" >&2
    exit 1
  fi
  if "${validator}" v1.5.1 1.1.2 "${invalid_tag}"; then
    echo "accepted invalid CrewAI image tag: ${invalid_tag}" >&2
    exit 1
  fi
done

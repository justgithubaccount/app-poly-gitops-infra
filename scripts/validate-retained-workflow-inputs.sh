#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 3; then
  echo "usage: $0 <gitops-release> <fastapi-image-tag> <crewai-image-tag>" >&2
  exit 2
fi

gitops_revision="$1"
fastapi_tag="$2"
crewai_tag="$3"

if ! [[ "${gitops_revision}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "gitops_revision must be an immutable vMAJOR.MINOR.PATCH release tag" >&2
  exit 2
fi

for image_tag in "${fastapi_tag}" "${crewai_tag}"; do
  if ! [[ "${image_tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "expected image tags must use MAJOR.MINOR.PATCH" >&2
    exit 2
  fi
done

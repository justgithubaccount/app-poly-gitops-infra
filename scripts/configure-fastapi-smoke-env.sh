#!/usr/bin/env bash
set -euo pipefail

namespace="${1:?usage: configure-fastapi-smoke-env.sh NAMESPACE DEPLOYMENT SECRET [CONTAINER]}"
deployment="${2:?usage: configure-fastapi-smoke-env.sh NAMESPACE DEPLOYMENT SECRET [CONTAINER]}"
secret_name="${3:?usage: configure-fastapi-smoke-env.sh NAMESPACE DEPLOYMENT SECRET [CONTAINER]}"
container_name="${4:-${deployment}}"
kubectl_bin="${KUBECTL_BIN:-kubectl}"

patch="$(jq -nc \
  --arg container "${container_name}" \
  --arg secret "${secret_name}" \
  '{
    spec: {
      template: {
        spec: {
          containers: [{
            name: $container,
            env: [
              {
                name: "OPENROUTER_API_KEY",
                valueFrom: {
                  secretKeyRef: {
                    name: $secret,
                    key: "OPENROUTER_API_KEY"
                  }
                }
              },
              {
                name: "OPENROUTER_API_URL",
                value: "https://api.openai.com/v1/chat/completions"
              },
              {
                name: "OPENROUTER_MODEL",
                value: "gpt-4o-mini"
              }
            ]
          }]
        }
      }
    }
  }')"

"${kubectl_bin}" -n "${namespace}" patch deployment "${deployment}" \
  --type strategic \
  --patch "${patch}"

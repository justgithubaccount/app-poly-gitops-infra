#!/usr/bin/env sh
set -eu

base_url="${1:?usage: fastapi-runtime-smoke.sh BASE_URL}"
base_url="${base_url%/}"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

request() {
  method="$1"
  path="$2"
  output="$3"
  data="${4:-}"
  if test -n "${data}"; then
    curl --silent --show-error --fail-with-body \
      --request "${method}" \
      --header 'Content-Type: application/json' \
      --data "${data}" \
      --output "${output}" \
      "${base_url}${path}"
  else
    curl --silent --show-error --fail-with-body \
      --request "${method}" \
      --output "${output}" \
      "${base_url}${path}"
  fi
}

assert_reply() {
  response_file="$1"
  grep -Eq '"reply"[[:space:]]*:[[:space:]]*"[^"[:space:]][^"]*"' "${response_file}"
  ! grep -Eiq 'ошибка api|http ошибка|invalid key|authentication|unauthorized' "${response_file}"
}

request GET / "${work_dir}/root.json"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' "${work_dir}/root.json"
grep -Eq '"service"[[:space:]]*:[[:space:]]*"Chat Microservice"' "${work_dir}/root.json"

request GET /health "${work_dir}/health.json"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' "${work_dir}/health.json"

project_name="runtime-smoke-$(date +%s)"
request POST /api/v1/projects "${work_dir}/project.json" \
  "{\"name\":\"${project_name}\"}"
project_id="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${work_dir}/project.json")"
test -n "${project_id}"
grep -Fq "\"name\": \"${project_name}\"" "${work_dir}/project.json" || \
  grep -Fq "\"name\":\"${project_name}\"" "${work_dir}/project.json"

request GET /api/v1/projects "${work_dir}/projects.json"
grep -Fq "${project_id}" "${work_dir}/projects.json"

request POST /api/v1/chat "${work_dir}/chat.json" \
  '{"messages":[{"role":"user","content":"Reply briefly with FASTAPI_SMOKE_OK."}]}'
assert_reply "${work_dir}/chat.json"

project_message="project-history-${project_id}"
request POST "/api/v1/projects/${project_id}/chat" "${work_dir}/project-chat.json" \
  "{\"messages\":[{\"role\":\"user\",\"content\":\"${project_message}\"}]}"
assert_reply "${work_dir}/project-chat.json"

request GET "/api/v1/projects/${project_id}/history" "${work_dir}/history.json"
grep -Fq "${project_id}" "${work_dir}/history.json"
grep -Fq "${project_message}" "${work_dir}/history.json"

http_code="$(curl --silent --show-error --output "${work_dir}/missing.json" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{"messages":[{"role":"user","content":"test"}]}' \
  "${base_url}/api/v1/projects/does-not-exist/chat")"
test "${http_code}" = "404"

http_code="$(curl --silent --show-error --output "${work_dir}/invalid.json" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{"messages":[]}' \
  "${base_url}/api/v1/chat")"
test "${http_code}" = "422"

printf '%s\n' "FastAPI runtime smoke passed: health, projects, live chat, project chat, history, and validation"

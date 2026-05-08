#!/bin/bash
set -euo pipefail

if [ -z "${RUNNER_URL:-}" ]; then
  echo "RUNNER_URL 未設定" >&2
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN 未設定" >&2
  exit 1
fi

api_base="${GITHUB_API_URL:-https://api.github.com}"
accept_header="Accept: application/vnd.github+json"
version_header="X-GitHub-Api-Version: 2022-11-28"
auth_header="Authorization: Bearer ${GITHUB_TOKEN}"

normalize_url() {
  printf '%s' "$1" | sed 's#/*$##'
}

runner_url="$(normalize_url "$RUNNER_URL")"

if [[ "$runner_url" =~ ^https://github.com/([^/]+)/([^/]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  endpoint="${api_base}/repos/${owner}/${repo}/actions/runners/registration-token"
elif [[ "$runner_url" =~ ^https://github.com/([^/]+)$ ]]; then
  org="${BASH_REMATCH[1]}"
  endpoint="${api_base}/orgs/${org}/actions/runners/registration-token"
else
  echo "無法解析 RUNNER_URL：僅支援 https://github.com/<owner>/<repo> 或 https://github.com/<org>" >&2
  exit 1
fi

response_file="$(mktemp)"
http_code="$({ curl -fsS -o "$response_file" -w '%{http_code}' \
  -X POST \
  -H "$accept_header" \
  -H "$version_header" \
  -H "$auth_header" \
  "$endpoint"; } || true)"

if [ "$http_code" != "201" ]; then
  echo "向 GitHub 申請 registration token 失敗（HTTP ${http_code:-unknown}）" >&2
  if [ -s "$response_file" ]; then
    jq -r '.message // "GitHub API request failed"' "$response_file" >&2 || true
  fi
  rm -f "$response_file"
  exit 1
fi

token="$(jq -r '.token // empty' "$response_file")"
rm -f "$response_file"

if [ -z "$token" ]; then
  echo "GitHub API 未回傳 registration token" >&2
  exit 1
fi

printf '%s' "$token"

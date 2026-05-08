#!/bin/bash
set -euo pipefail

cd /actions-runner

if [ -z "${RUNNER_URL:-}" ]; then
  echo "RUNNER_URL 未設定"
  exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LABELS="${RUNNER_LABELS:-docker}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
FORCE_RECONFIGURE="${FORCE_RECONFIGURE:-true}"
RUNNER_ALLOW_RUNASROOT="${RUNNER_ALLOW_RUNASROOT:-0}"

get_runner_token() {
  if [ -n "${RUNNER_TOKEN:-}" ]; then
    echo "Using provided RUNNER_TOKEN" >&2
    printf '%s' "$RUNNER_TOKEN"
    return 0
  fi

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "RUNNER_TOKEN 與 GITHUB_TOKEN 都未設定，無法 bootstrap runner" >&2
    exit 1
  fi

  echo "RUNNER_TOKEN 未提供，改用 GITHUB_TOKEN 動態向 GitHub 申請 registration token" >&2
  /scripts/get-registration-token.sh
}

cleanup_runner_config() {
  if [ ! -f .runner ]; then
    return 0
  fi

  echo "Existing runner config detected; removing previous registration before reconfigure..." >&2
  local remove_token
  remove_token="$(get_runner_token)"
  ./config.sh remove --unattended --token "$remove_token" || {
    echo "Warning: existing runner removal failed; continuing with local cleanup" >&2
  }
  rm -f .runner .credentials .credentials_rsaparams .env .path
  rm -rf _diag
}

shutdown() {
  if [ -f .runner ]; then
    echo "Stopping runner and removing registration..." >&2
    local remove_token
    remove_token="$(get_runner_token)"
    ./config.sh remove --unattended --token "$remove_token" || {
      echo "Warning: runner deregistration during shutdown failed" >&2
    }
  fi
}

trap 'shutdown; exit 130' INT
trap 'shutdown; exit 143' TERM
trap 'shutdown' EXIT

if [ "$FORCE_RECONFIGURE" = "true" ]; then
  cleanup_runner_config
fi

echo "Configuring runner..."
registration_token="$(get_runner_token)"
./config.sh \
  --unattended \
  --replace \
  --url "$RUNNER_URL" \
  --token "$registration_token" \
  --name "$RUNNER_NAME" \
  --work "$RUNNER_WORKDIR" \
  --labels "$RUNNER_LABELS" \
  --runnergroup "$RUNNER_GROUP"

echo "Starting runner..."
./run.sh &
wait $!

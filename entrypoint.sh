#!/bin/bash
set -euo pipefail

if [ -z "${RUNNER_URL:-}" ]; then
  echo "RUNNER_URL 未設定"
  exit 1
fi

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LABELS="${RUNNER_LABELS:-docker}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"

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

trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -f .runner ]; then
  echo "Configuring runner..."
  registration_token="$(get_runner_token)"
  ./config.sh \
    --unattended \
    --url "$RUNNER_URL" \
    --token "$registration_token" \
    --name "$RUNNER_NAME" \
    --work "$RUNNER_WORKDIR" \
    --labels "$RUNNER_LABELS" \
    --runnergroup "$RUNNER_GROUP"
fi

echo "Starting runner..."
./run.sh &
wait $!

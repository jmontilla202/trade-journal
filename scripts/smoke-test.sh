#!/usr/bin/env bash

set -Eeuo pipefail

API_URL="${API_URL:-http://localhost:8081}"
COMPOSE_FILE="${COMPOSE_FILE:-compose.dev.yaml}"
ENV_FILE="${ENV_FILE:-.env}"

SESSION_DATE="2099-01-15"
ENTRY_TIME="2099-01-15T14:30:00Z"

EXIT_TIME="2099-01-15T14:45:00Z"

TRADE_UUID=""

blue() {
  printf '\033[0;34m%s\033[0m\n' "$1"
}

green() {
  printf '\033[0;32m%s\033[0m\n' "$1"
}

red() {
  printf '\033[0;31m%s\033[0m\n' "$1" >&2
}


require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    red "Required command not found: $1"

    exit 1
  fi
}

cleanup() {
  if [[ -z "${TRADE_UUID}" ]]; then
    return
  fi

  blue "Removing smoke-test trade ${TRADE_UUID}"

  docker compose \
    --env-file "${ENV_FILE}" \
    --file "${COMPOSE_FILE}" \
    exec \
    --no-TTY \
    postgres \
    psql \
    --username trade_journal \
    --dbname trade_journal \
    --set ON_ERROR_STOP=1 \
    --command "DELETE FROM trades WHERE id = '${TRADE_UUID}'::uuid;" \
    >/dev/null 2>&1 || true
}

fail() {
  red "Smoke test failed: $1"
  exit 1
}

request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "${body}" ]]; then
    curl \
      --silent \
      --show-error \
      --fail-with-body \
      --request "${method}" \
      --header "Accept: application/json" \
      --header "Content-Type: application/json" \
      --data "${body}" \
      "${API_URL}${path}"
  else
    curl \
      --silent \
      --show-error \
      --fail-with-body \
      --request "${method}" \
      --header "Accept: application/json" \
      "${API_URL}${path}"
  fi
}

assert_json() {
  local json="$1"
  local expression="$2"
  local message="$3"

  if ! jq --exit-status "${expression}" <<<"${json}" >/dev/null; then
    red "Response was:"
    jq . <<<"${json}" >&2 || printf '%s\n' "${json}" >&2
    fail "${message}"
  fi
}

wait_for_api() {
  local attempts=60

  blue "Waiting for API readiness at ${API_URL}"


  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl \
      --silent \
      --fail \
      "${API_URL}/api/v1/health/ready" \
      >/dev/null 2>&1; then
      green "API is ready"
      return

    fi

    sleep 1
  done

  fail "API did not become ready within ${attempts} seconds"
}

trap cleanup EXIT


require_command curl
require_command jq
require_command docker

wait_for_api

blue "Checking liveness"

LIVE_RESPONSE="$(request GET "/api/v1/health/live")"

assert_json \
  "${LIVE_RESPONSE}" \
  '.status == "alive"' \
  "liveness endpoint returned an unexpected response"

blue "Checking seeded account"

ACCOUNTS_RESPONSE="$(request GET "/api/v1/accounts")"

assert_json \
  "${ACCOUNTS_RESPONSE}" \
  'length >= 1' \
  "no active accounts were returned"

ACCOUNT_ID="$(
  jq --raw-output \
    '.[] | select(.name == "Local Simulation") | .id' \
    <<<"${ACCOUNTS_RESPONSE}" |
    head -n 1
)"

if [[ -z "${ACCOUNT_ID}" || "${ACCOUNT_ID}" == "null" ]]; then
  fail "Local Simulation account was not found"
fi

blue "Checking ES instrument configuration"

INSTRUMENTS_RESPONSE="$(request GET "/api/v1/instruments")"


assert_json \
  "${INSTRUMENTS_RESPONSE}" \
  '
    any(
      .[];
      .symbol == "ES"
      and (.tickSize | tonumber) == 0.25
      and (.tickValue | tonumber) == 12.5
    )

  ' \
  "ES instrument configuration is incorrect"

blue "Creating draft trade"

CREATE_BODY="$(
  jq --null-input \
    --arg sessionDate "${SESSION_DATE}" \
    --arg accountId "${ACCOUNT_ID}" \
    --arg entryTime "${ENTRY_TIME}" \
    '{
      sessionDate: $sessionDate,
      accountId: $accountId,
      instrument: "ES",
      direction: "SHORT",
      contracts: 1,
      entryTime: $entryTime,
      entryPrice: 7722.25,
      initialStopPrice: 7725.25,
      initialStopReference: "Smoke test stop",
      plannedTargetPrice: 7718.00,
      plannedTargetReference: "Smoke test target",
      setup: "Automated smoke test",
      primaryLocation: "VAL",
      secondaryLocation: "EMA21",
      trigger: "Reversal bar",
      notes: "This trade should be deleted automatically"
    }'
)"

DRAFT_RESPONSE="$(
  request POST "/api/v1/trades" "${CREATE_BODY}"
)"

TRADE_UUID="$(jq --raw-output '.id' <<<"${DRAFT_RESPONSE}")"

if [[ -z "${TRADE_UUID}" || "${TRADE_UUID}" == "null" ]]; then
  fail "draft response did not include a trade UUID"
fi

assert_json \
  "${DRAFT_RESPONSE}" \
  '
    .status == "DRAFT"
    and .tradeId == null
    and .tradeNumber == null
    and .instrument.symbol == "ES"
    and .direction == "SHORT"
    and .contracts == 1
  ' \
  "draft response contains unexpected values"

green "Draft created: ${TRADE_UUID}"

blue "Fetching persisted draft"

FETCHED_DRAFT="$(
  request GET "/api/v1/trades/${TRADE_UUID}"
)"

assert_json \
  "${FETCHED_DRAFT}" \
  "
    .id == \"${TRADE_UUID}\"
    and .status == \"DRAFT\"
    and .version == 1
  " \
  "persisted draft does not match the created draft"

blue "Updating draft"

UPDATE_BODY="$(
  jq \
    '.notes = "Updated by smoke test"
     | .setup = "Updated automated smoke test"' \
    <<<"${CREATE_BODY}"
)"

UPDATED_DRAFT="$(
  request PUT "/api/v1/trades/${TRADE_UUID}" "${UPDATE_BODY}"
)"

assert_json \
  "${UPDATED_DRAFT}" \
  '
    .status == "DRAFT"
    and .notes == "Updated by smoke test"
    and .setup == "Updated automated smoke test"
    and .version == 2
  ' \
  "draft update failed"

blue "Opening trade"

OPEN_RESPONSE="$(
  request POST "/api/v1/trades/${TRADE_UUID}/open"
)"

assert_json \
  "${OPEN_RESPONSE}" \
  '
    .status == "OPEN"
    and .tradeId != null
    and .tradeNumber != null
    and .version == 3
  ' \
  "trade did not transition to OPEN"

TRADE_NUMBER="$(
  jq --raw-output '.tradeNumber' <<<"${OPEN_RESPONSE}"
)"

green "Trade opened with session number ${TRADE_NUMBER}"

blue "Confirming that an open trade cannot be opened twice"


DUPLICATE_OPEN_STATUS="$(
  curl \
    --silent \
    --output /tmp/trade-journal-duplicate-open.json \
    --write-out "%{http_code}" \
    --request POST \
    "${API_URL}/api/v1/trades/${TRADE_UUID}/open"
)"

if [[ "${DUPLICATE_OPEN_STATUS}" != "409" ]]; then
  cat /tmp/trade-journal-duplicate-open.json >&2 || true
  fail "opening an already-open trade should return HTTP 409"
fi

blue "Closing trade"

CLOSE_BODY="$(
  jq --null-input \
    --arg exitTime "${EXIT_TIME}" \
    '{
      exitTime: $exitTime,
      exitPrice: 7718.00,
      fees: 3.50
    }'
)"

CLOSE_RESPONSE="$(
  request POST \
    "/api/v1/trades/${TRADE_UUID}/close" \
    "${CLOSE_BODY}"
)"

assert_json \
  "${CLOSE_RESPONSE}" \
  '
    def approximately($expected; $tolerance):
      ((tonumber - $expected) | fabs) <= $tolerance;

    .status == "CLOSED"
    and (.grossPnl | approximately(212.50; 0.001))
    and (.fees | approximately(3.50; 0.001))
    and (.netPnl | approximately(209.00; 0.001))
    and (.plannedRiskPoints | approximately(3.00; 0.001))
    and (.plannedRiskUsd | approximately(150.00; 0.001))
    and (.realizedR | approximately(1.393333; 0.000001))
    and .version == 4
  ' \
  "closed-trade calculations are incorrect"

green "P&L and realized R calculations are correct"

blue "Confirming that a closed trade cannot be closed twice"


DUPLICATE_CLOSE_STATUS="$(
  curl \
    --silent \
    --output /tmp/trade-journal-duplicate-close.json \
    --write-out "%{http_code}" \
    --request POST \
    --header "Content-Type: application/json" \
    --data "${CLOSE_BODY}" \
    "${API_URL}/api/v1/trades/${TRADE_UUID}/close"
)"

if [[ "${DUPLICATE_CLOSE_STATUS}" != "409" ]]; then
  cat /tmp/trade-journal-duplicate-close.json >&2 || true
  fail "closing an already-closed trade should return HTTP 409"
fi

blue "Checking recent-trade listing"

TRADES_RESPONSE="$(request GET "/api/v1/trades?limit=100")"


assert_json \
  "${TRADES_RESPONSE}" \
  "
    any(
      .[];
      .id == \"${TRADE_UUID}\"
      and .status == \"CLOSED\"
    )
  " \
  "closed trade was not found in the recent-trades endpoint"


green "First-slice smoke test passed"


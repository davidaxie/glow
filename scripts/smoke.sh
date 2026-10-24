#!/usr/bin/env bash
# Owner: A1. Calls every operation in the generated contract on a running server and checks
# its status, so a route that's missing, crashing or skipping sign-in shows up at once.
#
#   scripts/smoke.sh                                    # signed out
#   GLOW_TOKEN=$(scripts/dev-token.sh) scripts/smoke.sh # signed in as a throwaway test person
#
# What passes:
#   - signed out, every user route answers 401, and so does the cron route without its secret
#   - signed in (and for public routes, and cron with its secret): 501 while it's still a
#     stub, or, once built, any status the contract declares for that operation, plus 400
#     and 404 (the sample request has an empty body and IDs that don't exist). Never a 500.
#   - test sign-in answers 404 unless ALLOW_TEST_LOGIN is on (D6)
#   - a path outside the contract answers a JSON 404
#
# Options (environment):
#   GLOW_API           base URL, default http://localhost:3000 (agent-env.sh sets it)
#   GLOW_TOKEN         a Supabase access token for a local test person
#   GLOW_SMOKE_STRICT  1 to require 501 everywhere, for a fresh skeleton
#
# Reads CRON_SECRET and ALLOW_TEST_LOGIN from server/.env.local. Exits 1 on any failure.
set -euo pipefail

API="${GLOW_API:-http://localhost:3000}"
TOKEN="${GLOW_TOKEN:-}"
STRICT="${GLOW_SMOKE_STRICT:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

from_env_file() {
  [[ -f "$ROOT/server/.env.local" ]] || return 0
  grep -E "^$1=" "$ROOT/server/.env.local" | head -n1 | cut -d= -f2- || true
}
CRON_SECRET="${CRON_SECRET:-$(from_env_file CRON_SECRET)}"
TEST_LOGIN="${ALLOW_TEST_LOGIN:-$(from_env_file ALLOW_TEST_LOGIN)}"

# Every operation: METHOD PATH AUTH BODY OPERATION_ID OWNER STATUSES.
ENDPOINTS=()
while IFS= read -r line; do ENDPOINTS+=("$line"); done < <(node "$ROOT/scripts/list-operations.mjs")
[[ "${#ENDPOINTS[@]}" -gt 0 ]] || { echo "smoke: no operations found in the contract" >&2; exit 1; }

# For a request that should reach the handler: 501, or anything the contract allows.
reachable() {
  if [[ -n "$STRICT" ]]; then echo "501"; else echo "501,400,404,$1"; fi
}

pass=0
fail=0
stubs=0
for line in "${ENDPOINTS[@]}"; do
  read -r method path auth body op owner statuses <<<"$line"
  [[ "$op" == testLogin ]] && auth=dev
  args=(-s -o /dev/null -w '%{http_code}' -X "$method" "$API$path")
  case "$body" in
    json) args+=(-H 'content-type: application/json' --data '{}') ;;
    multipart) args+=(-F 'placeholder=1') ;;
  esac

  case "$auth" in
    user)
      if [[ -n "$TOKEN" ]]; then
        args+=(-H "authorization: Bearer $TOKEN")
        want="$(reachable "$statuses")"
      else
        want=401
      fi
      ;;
    cron)
      if [[ -n "$CRON_SECRET" ]]; then
        args+=(-H "authorization: Bearer $CRON_SECRET")
        want="$(reachable "$statuses")"
      else
        want=401
      fi
      ;;
    dev)
      if [[ "$TEST_LOGIN" == "1" || "$TEST_LOGIN" == "true" ]]; then
        want="$(reachable "$statuses")"
      else
        want=404
      fi
      ;;
    *) want="$(reachable "$statuses")" ;;
  esac

  got="$(curl "${args[@]}" || echo 000)"
  [[ "$got" == 501 ]] && stubs=$((stubs + 1))
  if [[ ",$want," == *",$got,"* ]]; then
    pass=$((pass + 1))
    printf '  ok    %-6s %-56s %s\n' "$method" "$path" "$got"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-6s %-56s got %s, want one of %s (%s, %s)\n' "$method" "$path" "$got" "$want" "$op" "$owner"
  fi
done

# Paths outside the contract are a plain JSON 404.
got="$(curl -s -o /dev/null -w '%{http_code}' "$API/api/not-in-the-contract" || echo 000)"
if [[ "$got" == 404 ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "  FAIL  unknown /api path gave $got, want 404"
fi

echo "smoke: $pass passed, $fail failed, $stubs still stubs, against $API"
[[ "$fail" -eq 0 ]]

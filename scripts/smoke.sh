#!/usr/bin/env bash
# Hits every endpoint in the API contract on a running server and checks the status.
#
#   scripts/smoke.sh                      # no token: user routes must answer 401
#   GLOW_TOKEN=$(scripts/dev-token.sh) scripts/smoke.sh   # signed in: stubs answer 501
#
# Options (environment):
#   GLOW_API      base URL, default http://localhost:3000
#   GLOW_TOKEN    a Supabase access token for a local test person
#   GLOW_EXPECT   status a built-out stub should give with a token, default 501
#
# Reads CRON_SECRET from server/.env.local for the cron route. Exits 1 on any mismatch.
set -euo pipefail

API="${GLOW_API:-http://localhost:3000}"
TOKEN="${GLOW_TOKEN:-}"
EXPECT="${GLOW_EXPECT:-501}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CRON_SECRET="${CRON_SECRET:-}"
if [[ -z "$CRON_SECRET" && -f "$ROOT/server/.env.local" ]]; then
  CRON_SECRET="$(grep -E '^CRON_SECRET=' "$ROOT/server/.env.local" | head -n1 | cut -d= -f2- || true)"
fi
TEST_LOGIN="${ALLOW_TEST_LOGIN:-}"
if [[ -z "$TEST_LOGIN" && -f "$ROOT/server/.env.local" ]]; then
  TEST_LOGIN="$(grep -E '^ALLOW_TEST_LOGIN=' "$ROOT/server/.env.local" | head -n1 | cut -d= -f2- || true)"
fi

ID=11111111-1111-4111-8111-111111111111

# method  path  auth(user|public|cron|dev)  body(json|multipart|none)
ENDPOINTS=(
  "GET    /api/me                                 user   none"
  "PUT    /api/me/profile                         user   json"
  "POST   /api/me/photos                          user   multipart"
  "DELETE /api/me/photos/$ID                      user   none"
  "POST   /api/dev/test-login                     dev    json"
  "POST   /api/me/pause                           user   json"
  "DELETE /api/me                                 user   none"
  "POST   /api/devices                            user   json"
  "DELETE /api/devices/$ID                        user   none"
  "POST   /api/rooms/resolve                      user   json"
  "POST   /api/rooms/$ID/join                     user   json"
  "POST   /api/rooms/$ID/leave                    user   none"
  "POST   /api/rooms/$ID/checkin                  user   multipart"
  "GET    /api/cards/$ID/image                    user   none"
  "POST   /api/rooms/$ID/deck                     user   json"
  "POST   /api/rooms/$ID/taps                     user   json"
  "GET    /api/matches                            user   none"
  "GET    /api/matches/$ID                        user   none"
  "GET    /api/matches/$ID/photos/0               user   none"
  "POST   /api/matches/$ID/choice                 user   json"
  "GET    /api/matches/$ID/glow                   user   none"
  "POST   /api/matches/$ID/glow/met               user   none"
  "POST   /api/matches/$ID/glow/cancel            user   none"
  "GET    /api/matches/$ID/messages               user   none"
  "POST   /api/matches/$ID/messages               user   json"
  "POST   /api/matches/$ID/unmatch                user   none"
  "POST   /api/blocks                             user   json"
  "POST   /api/reports                            user   json"
  "POST   /api/abuse/capture                      user   json"
  "GET    /api/cron/purge                         cron   none"
  "GET    /.well-known/apple-app-site-association public none"
  "GET    /r/demo                                 public none"
)

pass=0
fail=0
for line in "${ENDPOINTS[@]}"; do
  read -r method path auth body <<<"$line"
  args=(-s -o /dev/null -w '%{http_code}' -X "$method" "$API$path")
  case "$body" in
    json) args+=(-H 'content-type: application/json' --data '{}') ;;
    multipart) args+=(-F 'placeholder=1') ;;
  esac

  case "$auth" in
    user)
      if [[ -n "$TOKEN" ]]; then
        args+=(-H "authorization: Bearer $TOKEN")
        want="$EXPECT"
      else
        want=401
      fi
      ;;
    cron)
      if [[ -n "$CRON_SECRET" ]]; then
        args+=(-H "authorization: Bearer $CRON_SECRET")
        want="$EXPECT"
      else
        want=401
      fi
      ;;
    dev)
      if [[ "$TEST_LOGIN" == "1" || "$TEST_LOGIN" == "true" ]]; then want="$EXPECT"; else want=404; fi
      ;;
    public) want="$EXPECT" ;;
  esac

  got="$(curl "${args[@]}" || echo 000)"
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    printf '  ok    %-6s %-42s %s\n' "$method" "$path" "$got"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-6s %-42s got %s, want %s\n' "$method" "$path" "$got" "$want"
  fi
done

# Paths outside the contract are a plain JSON 404.
got="$(curl -s -o /dev/null -w '%{http_code}' "$API/api/not-in-the-contract" || echo 000)"
if [[ "$got" == 404 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL  unknown /api path gave $got, want 404"; fi

echo "smoke: $pass passed, $fail failed against $API"
[[ "$fail" -eq 0 ]]

#!/usr/bin/env bash
# Prints a Supabase access token for a brand-new throwaway test person on the LOCAL
# Supabase, for curl and scripts/smoke.sh. Refuses to run against anything but
# localhost. Until B1's POST /api/dev/test-login exists, this is the way to get one.
#
#   TOKEN=$(scripts/dev-token.sh)
#   curl -H "authorization: Bearer $TOKEN" http://localhost:3000/api/me
#
# Reads SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY from the
# environment, or from server/.env.local.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/server/.env.local"

read_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" && -f "$ENV_FILE" ]]; then
    value="$(grep -E "^${name}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  fi
  printf '%s' "$value"
}

URL="$(read_var SUPABASE_URL)"
ANON="$(read_var SUPABASE_ANON_KEY)"
SERVICE="$(read_var SUPABASE_SERVICE_ROLE_KEY)"

if [[ -z "$URL" || -z "$ANON" || -z "$SERVICE" ]]; then
  echo "dev-token: set SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY (run pnpm env:setup)." >&2
  exit 1
fi
case "$URL" in
  http://127.0.0.1:* | http://localhost:* | http://\[::1\]:*) ;;
  *)
    echo "dev-token: refusing to create test users on $URL. Local Supabase only." >&2
    exit 1
    ;;
esac

suffix="$(node -e 'process.stdout.write(require("node:crypto").randomBytes(6).toString("hex"))')"
password="$(node -e 'process.stdout.write(require("node:crypto").randomBytes(24).toString("base64url"))')"
email="dev-token+${suffix}@glow.test"

body="$(node -e 'process.stdout.write(JSON.stringify({ email: process.argv[1], password: process.argv[2], email_confirm: true, user_metadata: { test_data: true } }))' "$email" "$password")"
curl -sf -X POST "$URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE" -H "authorization: Bearer $SERVICE" -H 'content-type: application/json' \
  --data "$body" >/dev/null || {
  echo "dev-token: could not create a test user. Is the local Supabase running (pnpm db:start)?" >&2
  exit 1
}

login="$(node -e 'process.stdout.write(JSON.stringify({ email: process.argv[1], password: process.argv[2] }))' "$email" "$password")"
curl -sf -X POST "$URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H 'content-type: application/json' --data "$login" |
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const t=JSON.parse(s).access_token;if(!t){process.exit(1)}process.stdout.write(t+"\n")})'

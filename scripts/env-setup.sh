#!/usr/bin/env bash
# Creates server/.env.local for local development:
#   1. copies server/.env.example
#   2. fills in the Supabase URL and keys from `supabase status`, if it's running
#   3. replaces the placeholder secrets with fresh random ones
#
#   pnpm env:setup            # keeps an existing server/.env.local
#   pnpm env:setup --force    # rewrites it
#   pnpm env:setup --test-login   # also sets ALLOW_TEST_LOGIN=1 (local Supabase only)
#
# Never prints secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$ROOT/server/.env.example"
TARGET="$ROOT/server/.env.local"
FORCE=0
TEST_LOGIN=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --test-login) TEST_LOGIN=1 ;;
    *) echo "env-setup: unknown option $arg" >&2; exit 2 ;;
  esac
done

if [[ -f "$TARGET" && "$FORCE" -ne 1 ]]; then
  echo "env-setup: server/.env.local already exists. Use --force to rewrite it."
  exit 0
fi

cp "$EXAMPLE" "$TARGET"
chmod 600 "$TARGET"

set_var() {
  # Replaces NAME=... in the target file, without echoing the value.
  node -e '
    const fs = require("node:fs");
    const [file, name, value] = process.argv.slice(1);
    const lines = fs.readFileSync(file, "utf8").split("\n");
    const i = lines.findIndex((l) => l.startsWith(name + "="));
    if (i === -1) lines.push(`${name}=${value}`); else lines[i] = `${name}=${value}`;
    fs.writeFileSync(file, lines.join("\n"));
  ' "$TARGET" "$1" "$2"
}

secret() { node -e 'process.stdout.write(require("node:crypto").randomBytes(32).toString("base64url"))'; }

set_var JOIN_TICKET_SECRET "$(secret)"
set_var CARD_URL_SECRET "$(secret)"
set_var CRON_SECRET "$(secret)"

SUPABASE_BIN="$(command -v supabase || true)"
if [[ -z "$SUPABASE_BIN" && -x "$HOME/.local/bin/supabase" ]]; then SUPABASE_BIN="$HOME/.local/bin/supabase"; fi

if [[ -n "$SUPABASE_BIN" && -f "$ROOT/supabase/config.toml" ]] &&
  status="$(cd "$ROOT" && "$SUPABASE_BIN" status -o env 2>/dev/null)"; then
  get() { printf '%s\n' "$status" | grep -E "^$1=" | head -n1 | cut -d= -f2- | tr -d '"'; }
  api="$(get API_URL)"
  anon="$(get PUBLISHABLE_KEY)"; [[ -n "$anon" ]] || anon="$(get ANON_KEY)"
  service="$(get SECRET_KEY)"; [[ -n "$service" ]] || service="$(get SERVICE_ROLE_KEY)"
  if [[ -n "$api" && -n "$anon" && -n "$service" ]]; then
    set_var SUPABASE_URL "$api"
    set_var SUPABASE_ANON_KEY "$anon"
    set_var SUPABASE_SERVICE_ROLE_KEY "$service"
    echo "env-setup: Supabase URL and keys copied from 'supabase status' ($api)."
  fi
else
  echo "env-setup: local Supabase isn't running, so the default local keys from .env.example are kept."
  echo "           Start it with 'pnpm db:start', then run 'pnpm env:setup --force' to pick up its keys."
fi

if [[ "$TEST_LOGIN" -eq 1 ]]; then
  set_var ALLOW_TEST_LOGIN 1
  echo "env-setup: ALLOW_TEST_LOGIN=1 (test sign-in on, local only)."
fi

echo "env-setup: wrote server/.env.local with fresh JOIN_TICKET_SECRET, CARD_URL_SECRET and CRON_SECRET."

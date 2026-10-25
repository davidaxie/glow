#!/usr/bin/env bash
# Owner: A1. Keeps parallel agents on one Mac out of each other's way. Prints shell exports
# for one agent: its own Simulator names, its own server port, and the matching API URL.
#
#   eval "$(scripts/agent-env.sh B1)"
#   pnpm dev                      # http://localhost:3101
#   scripts/sim.sh setup A        # boots "Glow A (B1)" only
#   scripts/sim.sh build          # the app talks to http://localhost:3101
#   scripts/smoke.sh              # checks http://localhost:3101
#   scripts/sim.sh teardown       # deletes B1's Simulators when you're done
#
# Everyone shares the one local Supabase (the `glow` stack, API 54421, DB 54422). Agents
# that add migrations or need `db reset` get their own stack instead:
#
#   eval "$(scripts/agent-env.sh B4 --own-db)"   # copies supabase/, starts glow-b4 on its own ports
#   eval "$(scripts/agent-env.sh B4 --own-db --reset)"   # same, and reapplies migrations and seed
#   scripts/agent-env.sh B4 --stop-db            # stops glow-b4
#
# An own stack takes one of the Mac's shared `db` slots (mac-slots, one pool for every project;
# `mac-slots status`), held until --stop-db. If the pool is full, it waits for a free one.
#
# Everything except the exports goes to stderr, so the eval only sees exports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/slot-pool.sh
source "$ROOT/scripts/lib/slot-pool.sh"

usage() {
  cat >&2 <<'EOF'
usage: scripts/agent-env.sh <AGENT_ID> [--own-db [--reset] | --stop-db]
       scripts/agent-env.sh --list
EOF
  exit 2
}

# Agent ID, server port and own-database port block. Ports are 3090 + index; database
# blocks are 55000 + 10 x index (55110 to 55119 for B1). 3000 and the 544xx block stay
# for the main checkout and the shared stack.
TABLE='A1 1
A2 2
A3 3
B1 11
B2 12
B3 13
B4 14
B5 15
B6 16
B7 17
B8 18
B9 19
C1 21
C2 22
C3 23
C4 24
D1 31
D2 32
D3 33
D4 34
D5 35
E1 41
E2 42
E3 43
CHIPS 51
X1 61
X2 62
Y1 71'

if [ "${1:-}" = "--list" ]; then
  printf '%-4s %-6s %s\n' agent port own-db-api >&2
  while read -r id index; do
    printf '%-4s %-6s %s\n' "$id" "$((3090 + index))" "$((55000 + index * 10 + 1))" >&2
  done <<<"$TABLE"
  exit 0
fi

[ $# -ge 1 ] || usage
AGENT="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
shift
INDEX="$(awk -v id="$AGENT" '$1 == id { print $2 }' <<<"$TABLE")"
[ -n "$INDEX" ] || { echo "agent-env: unknown agent '$AGENT'. Run: scripts/agent-env.sh --list" >&2; exit 2; }

OWN_DB=0
RESET=0
STOP_DB=0
for arg in "$@"; do
  case "$arg" in
    --own-db) OWN_DB=1 ;;
    --reset) RESET=1 ;;
    --stop-db) STOP_DB=1 ;;
    *) usage ;;
  esac
done
[ "$RESET" -eq 0 ] || [ "$OWN_DB" -eq 1 ] || usage

PORT=$((3090 + INDEX))
DB_BASE=$((55000 + INDEX * 10))
LOWER="$(printf '%s' "$AGENT" | tr '[:upper:]' '[:lower:]')"
PROJECT_ID="glow-$LOWER"
STATE="${GLOW_AGENT_STATE_DIR:-$ROOT/.agent-state}/$LOWER"

SUPABASE_BIN="$(command -v supabase || true)"
if [ -z "$SUPABASE_BIN" ] && [ -x "$HOME/.local/bin/supabase" ]; then SUPABASE_BIN="$HOME/.local/bin/supabase"; fi

# The db slot this stack holds is recorded in $STATE/mac-slot ("<slot path> <owner pid>").
db_slot_valid() {
  local slot rpid
  [ -f "$STATE/mac-slot" ] || return 1
  read -r slot rpid <"$STATE/mac-slot"
  [ -n "$slot" ] && [ -d "$slot" ] && [ "$(pool_slot_pid "$slot")" = "$rpid" ] && kill -0 "$rpid" 2>/dev/null
}

# Gives the db slot back, if it's still the one this stack took.
release_db_slot() {
  local slot rpid
  [ -f "$STATE/mac-slot" ] || return 0
  read -r slot rpid <"$STATE/mac-slot"
  if [ -n "$slot" ] && [ -d "$slot" ] && [ "$(pool_slot_pid "$slot")" = "$rpid" ] && pool_on; then
    pool release "$slot" >/dev/null 2>&1 || true
  fi
  rm -f "$STATE/mac-slot"
}

if [ "$STOP_DB" -eq 1 ]; then
  [ -n "$SUPABASE_BIN" ] || { echo "agent-env: the supabase CLI isn't installed." >&2; exit 1; }
  [ -d "$STATE/supabase" ] || { echo "agent-env: $AGENT has no own database at $STATE." >&2; exit 1; }
  "$SUPABASE_BIN" stop --workdir "$STATE" --no-backup >&2
  release_db_slot
  echo "agent-env: stopped $PROJECT_ID." >&2
  exit 0
fi

q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

echo "export GLOW_AGENT_ID=$AGENT"
echo "export GLOW_SIM_A=$(q "Glow A ($AGENT)")"
echo "export GLOW_SIM_B=$(q "Glow B ($AGENT)")"
echo "export PORT=$PORT"
echo "export GLOW_API=http://localhost:$PORT"
echo "export GLOW_API_BASE_URL=http://localhost:$PORT"

[ "$OWN_DB" -eq 1 ] || exit 0

# --- Own database ---------------------------------------------------------------------------
[ -n "$SUPABASE_BIN" ] || { echo "agent-env: the supabase CLI isn't installed." >&2; exit 1; }
[ -f "$ROOT/supabase/config.toml" ] || { echo "agent-env: no supabase/config.toml in $ROOT." >&2; exit 1; }

# A fresh copy of this worktree's supabase/ (so new migrations come along), with its own
# project ID and ports. Docker containers are named supabase_*_glow-<id>.
mkdir -p "$STATE"
# Sync in place rather than delete and copy: Kong and GoTrue bind-mount single files (the email
# templates), and a mount keeps pointing at the old inode, so a deleted or replaced file leaves the
# running stack with a dangling mount (sign-in then falls back to the default magic-link email).
# --inplace keeps each file's inode; a restart below picks up changed templates or settings.
mkdir -p "$STATE/supabase"
config_before="$(shasum "$STATE/supabase/config.toml" 2>/dev/null | cut -d' ' -f1 || true)"
synced="$(rsync -a --checksum --delete --inplace --itemize-changes --exclude .temp --exclude .branches \
  "$ROOT/supabase/" "$STATE/supabase/")"

node - "$STATE/supabase/config.toml" "$PROJECT_ID" "$DB_BASE" <<'EOF'
const fs = require('node:fs');
const [file, projectId, base] = process.argv.slice(2);
const b = Number(base);
// Port settings by section. Every one is replaced, so nothing collides with the shared stack.
const ports = {
  api: { port: b + 1 },
  db: { port: b + 2, shadow_port: b },
  'db.pooler': { port: b + 5 },
  studio: { port: b + 3 },
  local_smtp: { port: b + 4 },
  inbucket: { port: b + 4 },
  analytics: { port: b + 6 },
  edge_runtime: { inspector_port: b + 7 },
};
let section = '';
const out = fs.readFileSync(file, 'utf8').split('\n').map((line) => {
  const header = /^\s*\[([^\]]+)\]\s*$/.exec(line);
  if (header) { section = header[1]; return line; }
  if (section === '' && /^\s*project_id\s*=/.test(line)) return `project_id = "${projectId}"`;
  const setting = /^(\s*)([a-z_]+)(\s*=\s*)\d+(.*)$/.exec(line);
  const value = setting && ports[section]?.[setting[2]];
  return value ? `${setting[1]}${setting[2]}${setting[3]}${value}${setting[4]}` : line;
});
fs.writeFileSync(file, out.join('\n'));
EOF

config_after="$(shasum "$STATE/supabase/config.toml" | cut -d' ' -f1)"
restart=0
if printf '%s\n' "$synced" | grep -q ' templates/'; then restart=1; fi
if [ -n "$config_before" ] && [ "$config_before" != "$config_after" ]; then restart=1; fi

api_port="$(awk '/^\[api\]/{s=1;next} /^\[/{s=0} s && /^port *=/{gsub(/[^0-9]/,"");print;exit}' "$STATE/supabase/config.toml")"
[ "$api_port" = "$((DB_BASE + 1))" ] || { echo "agent-env: couldn't move $PROJECT_ID to its own ports." >&2; exit 1; }

if [ "$restart" -eq 1 ] && "$SUPABASE_BIN" status --workdir "$STATE" >/dev/null 2>&1; then
  echo "agent-env: restarting $PROJECT_ID to pick up changed templates or settings (data is kept)" >&2
  "$SUPABASE_BIN" stop --workdir "$STATE" >&2
fi
# The shared pool: this stack needs a db slot while it runs, whether it's already up or about to
# start. Exit 4 means the pool stayed full for the whole wait.
if pool_on && ! db_slot_valid; then
  rm -f "$STATE/mac-slot"
  echo "agent-env: taking a database slot from the Mac's shared pool (waits if it's full)" >&2
  slot="$(MAC_SLOTS_WAIT_MAX="${GLOW_DB_SLOT_WAIT:-1800}" pool acquire db "$GLOW_POOL_PROJECT" "$(owner_pid)")" || {
    echo "agent-env: no database slot came free (mac-slots status shows who holds them)." >&2
    exit 4
  }
  printf '%s %s\n' "$slot" "$(pool_slot_pid "$slot")" >"$STATE/mac-slot"
fi
if ! "$SUPABASE_BIN" status --workdir "$STATE" >/dev/null 2>&1; then
  # Without mac-slots: at most GLOW_MAX_OWN_DBS (6) agent stacks at once on this Mac, besides the
  # shared one.
  others="$(docker ps --format '{{.Names}}' 2>/dev/null | sed -nE 's/^supabase_db_(glow-[a-z0-9]+)$/\1/p' | grep -vx "$PROJECT_ID" || true)"
  running="$(printf '%s' "$others" | grep -c . || true)"
  if ! pool_on && [ "$running" -ge "${GLOW_MAX_OWN_DBS:-6}" ]; then
    echo "agent-env: $running agent Supabase stacks are running ($(echo $others)), and the limit is ${GLOW_MAX_OWN_DBS:-6}. Try again when one stops." >&2
    exit 3
  fi
  echo "agent-env: starting $PROJECT_ID on ports $DB_BASE to $((DB_BASE + 7)) (this takes a minute)" >&2
  "$SUPABASE_BIN" start --workdir "$STATE" -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta >&2
fi
# A stopped stack starts from its old data volume, so --reset reapplies this worktree's
# migrations and seed whether the stack was already up or has just started.
if [ "$RESET" -eq 1 ]; then
  echo "agent-env: reapplying migrations and seed on $PROJECT_ID" >&2
  "$SUPABASE_BIN" db reset --workdir "$STATE" >&2
fi

status="$("$SUPABASE_BIN" status --workdir "$STATE" -o env 2>/dev/null)"
get() { printf '%s\n' "$status" | grep -E "^$1=" | head -n1 | cut -d= -f2- | tr -d '"'; }
api="$(get API_URL)"
anon="$(get PUBLISHABLE_KEY)"; [ -n "$anon" ] || anon="$(get ANON_KEY)"
service="$(get SECRET_KEY)"; [ -n "$service" ] || service="$(get SERVICE_ROLE_KEY)"
db="$(get DB_URL)"
[ -n "$api" ] && [ -n "$anon" ] && [ -n "$service" ] || { echo "agent-env: $PROJECT_ID didn't report its keys." >&2; exit 1; }

echo "export SUPABASE_URL=$(q "$api")"
echo "export SUPABASE_ANON_KEY=$(q "$anon")"
echo "export SUPABASE_SERVICE_ROLE_KEY=$(q "$service")"
echo "export GLOW_SUPABASE_URL=$(q "$api")"
echo "export GLOW_SUPABASE_ANON_KEY=$(q "$anon")"
# The local Postgres has no TLS; `supabase gen types --db-url` (codegen.sh) tries TLS unless told.
case "$db" in *sslmode=*) ;; *\?*) db="$db&sslmode=disable" ;; *) db="$db?sslmode=disable" ;; esac
echo "export GLOW_DB_URL=$(q "$db")"
echo "export GLOW_SUPABASE_WORKDIR=$(q "$STATE")"
echo "agent-env: $PROJECT_ID is up at $api. Run supabase commands with --workdir \"\$GLOW_SUPABASE_WORKDIR\"." >&2

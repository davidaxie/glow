#!/usr/bin/env bash
# Owner: A1. `pnpm db:start|stop|reset|test|status`, safe for parallel agents.
#
# - With GLOW_SUPABASE_WORKDIR set (scripts/agent-env.sh <ID> --own-db), every command runs
#   against that agent's own stack.
# - Otherwise it's the shared `glow` stack (API 54421, DB 54422). As an agent (GLOW_AGENT_ID
#   set), `stop` and `reset` are refused there, because other agents are using it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_BIN="$(command -v supabase || true)"
if [ -z "$SUPABASE_BIN" ] && [ -x "$HOME/.local/bin/supabase" ]; then SUPABASE_BIN="$HOME/.local/bin/supabase"; fi
[ -n "$SUPABASE_BIN" ] || { echo "db: the supabase CLI isn't installed (brew install supabase/tap/supabase)." >&2; exit 1; }

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
  start) args=(start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta) ;;
  stop) args=(stop) ;;
  reset) args=(db reset) ;;
  test) args=(test db) ;;
  status) args=(status) ;;
  *) echo "usage: scripts/db.sh start|stop|reset|test|status [supabase args]" >&2; exit 2 ;;
esac

if [ -n "${GLOW_SUPABASE_WORKDIR:-}" ]; then
  exec "$SUPABASE_BIN" "${args[@]}" --workdir "$GLOW_SUPABASE_WORKDIR" "$@"
fi

if [ -n "${GLOW_AGENT_ID:-}" ] && { [ "$command" = stop ] || [ "$command" = reset ]; }; then
  cat >&2 <<EOF
db: refusing to $command the shared glow stack (54421, 54422): other agents are using it.
    For your own stack: eval "\$(scripts/agent-env.sh $GLOW_AGENT_ID --own-db)", then run this again.
EOF
  exit 1
fi

cd "$ROOT"
exec "$SUPABASE_BIN" "${args[@]}" "$@"

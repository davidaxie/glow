#!/usr/bin/env bash
# Owner: A1. Runs both CI jobs from .github/workflows/ci.yml on this Mac, for when GitHub
# Actions is down. Run it from your own worktree, on a clean, committed tree:
#
#   scripts/ci-local.sh B1               # both jobs
#   scripts/ci-local.sh B1 --server-only # the Ubuntu job only (no iOS changes in your PR)
#
# It uses your agent slot (scripts/agent-env.sh): your own server port, your own Simulator
# ("Glow A (B1)") and your own Supabase stack (--own-db --reset, so the database matches
# this branch's migrations). Nothing shared is touched.
#
# The last line is the summary to paste into your PR, for example:
#   ci-local B1 3f2a9c1 (rebased on main 9de2799): ubuntu pass, macos pass, 14m02s
set -uo pipefail

# The worktree you run it from, so a copy of this script can check any branch.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ci-local: run it inside the repo." >&2; exit 2; }
cd "$ROOT"

AGENT="${1:-}"
[ -n "$AGENT" ] || { echo "usage: scripts/ci-local.sh <AGENT_ID> [--server-only]" >&2; exit 2; }
shift
IOS=1
for arg in "$@"; do
  case "$arg" in
    --server-only) IOS=0 ;;
    *) echo "ci-local: unknown option $arg" >&2; exit 2 ;;
  esac
done

LOGS="$ROOT/.agent-state/ci-local"
mkdir -p "$LOGS"
started=$(date +%s)
say() { printf '\n==> %s\n' "$*"; }

if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  echo "ci-local: commit or stash your changes first, so the result belongs to one SHA." >&2
  exit 2
fi
head="$(git rev-parse --short HEAD)"
git fetch -q origin main 2>/dev/null || true
main="$(git rev-parse --short origin/main 2>/dev/null || echo unknown)"
if git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
  base="rebased on main $main"
else
  base="NOT rebased on main $main"
fi

ubuntu=pass
macos=skipped
fail_step() {
  printf 'ci-local: FAILED at %s (log: %s)\n' "$1" "$2" >&2
}

run() { # run <job> <step name> <command...>; logs to .agent-state/ci-local/<step>.log
  local job="$1" name="$2"
  shift 2
  local log="$LOGS/$(printf '%s' "$name" | tr ' /' '__').log"
  printf '  %-44s' "$name"
  if "$@" >"$log" 2>&1; then
    echo ok
    return 0
  fi
  echo FAIL
  tail -25 "$log" | sed 's/^/    | /'
  fail_step "$name" "$log"
  if [ "$job" = ubuntu ]; then ubuntu=fail; else macos=fail; fi
  return 1
}

# --- Ubuntu job -----------------------------------------------------------------------------
say "Ubuntu job (server and database), as agent $AGENT"
eval "$(scripts/agent-env.sh "$AGENT" --own-db --reset 2>"$LOGS/own-db.log")" || {
  cat "$LOGS/own-db.log" >&2
  echo "ci-local: couldn't start your own Supabase stack." >&2
  exit 1
}
echo "  own stack: $SUPABASE_URL, server port: $PORT"
# The local stack's Postgres has no TLS, and `supabase gen types --db-url` tries TLS first.
case "${GLOW_DB_URL:-}" in
  *sslmode=*) ;;
  *\?*) export GLOW_DB_URL="$GLOW_DB_URL&sslmode=disable" ;;
  ?*) export GLOW_DB_URL="$GLOW_DB_URL?sslmode=disable" ;;
esac
# codegen.sh and pgTAP call `supabase` by name.
if ! command -v supabase >/dev/null 2>&1 && [ -x "$HOME/.local/bin/supabase" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

codegen_clean() {
  scripts/codegen.sh || return 1
  git diff --exit-code --stat || { echo "Generated files are stale. Run pnpm codegen and commit."; return 1; }
  local untracked
  untracked="$(git ls-files --others --exclude-standard)"
  [ -z "$untracked" ] || { echo "Codegen created files that aren't committed: $untracked"; return 1; }
}

env_check() {
  # A missing variable must stop the server at once, with a message naming it.
  local log="$LOGS/missing-env-server.log"
  SUPABASE_SERVICE_ROLE_KEY= pnpm --filter server exec next start -p "$PORT" >"$log" 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "The server started without SUPABASE_SERVICE_ROLE_KEY"; return 1; fi
  wait "$pid" && { echo "The server exited 0 without SUPABASE_SERVICE_ROLE_KEY"; return 1; }
  grep -q "SUPABASE_SERVICE_ROLE_KEY  is missing" "$log" || { cat "$log"; echo "No clear message"; return 1; }
}

smoke() {
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then echo "Port $PORT is in use. Stop your dev server first."; return 1; fi
  pnpm --filter server exec next start -p "$PORT" >"$LOGS/server.log" 2>&1 &
  local waited=0
  until curl -sf -o /dev/null "$GLOW_API/"; do
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt 60 ] || { cat "$LOGS/server.log"; return 1; }
  done
  local code=0
  scripts/smoke.sh || code=1
  GLOW_TOKEN="$(scripts/dev-token.sh)" scripts/smoke.sh || code=1
  local pid
  pid="$(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN || true)"
  [ -z "$pid" ] || kill $pid
  return $code
}

run ubuntu "Install" pnpm install --frozen-lockfile &&
  run ubuntu "Codegen is up to date" codegen_clean &&
  { [ -f server/.env.local ] || run ubuntu "Server environment" scripts/env-setup.sh; } &&
  run ubuntu "Typecheck" pnpm typecheck &&
  run ubuntu "Lint" pnpm lint &&
  run ubuntu "Prettier" pnpm format:check &&
  run ubuntu "Vitest" pnpm test &&
  run ubuntu "Build" pnpm build &&
  run ubuntu "A missing variable stops the server" env_check &&
  run ubuntu "Smoke test every endpoint" smoke &&
  run ubuntu "pgTAP" supabase test db --workdir "$GLOW_SUPABASE_WORKDIR"

# --- macOS job ------------------------------------------------------------------------------
if [ "$IOS" -eq 1 ] && [ "$ubuntu" = pass ]; then
  say "macOS job (iOS build and tests) on $GLOW_SIM_A"
  macos=pass
  export GLOW_CI=1
  run macos "SwiftFormat and SwiftLint" scripts/sim.sh lint &&
    run macos "xcodegen is deterministic" scripts/sim.sh verify-project &&
    run macos "Boot Glow A" scripts/sim.sh setup A &&
    run macos "Build" scripts/sim.sh build &&
    run macos "Unit and UI tests on Glow A" scripts/sim.sh test
fi

elapsed=$(($(date +%s) - started))
summary="ci-local $AGENT $head ($base): ubuntu $ubuntu, macos $macos, $((elapsed / 60))m$(printf '%02d' $((elapsed % 60)))s"
echo
echo "$summary"
[ "$ubuntu" = pass ] && [ "$macos" != fail ] && [[ "$base" != NOT* ]]

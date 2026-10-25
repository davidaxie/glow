#!/usr/bin/env bash
# Owner: D1. Runs end-to-end journeys on Glow A, with person B played by scripts/e2e/player-b.ts.
#
#   eval "$(scripts/agent-env.sh <ID>)"   # first, in every shell (your Simulators, port and API)
#   scripts/e2e/run.sh full               # check in, tap, mutual, Find, glow, We met
#   scripts/e2e/run.sh chat               # mutual, Just chat, a message each way
#   scripts/e2e/run.sh block              # mutual, chat, A blocks B from the chat; it's gone for B
#   scripts/e2e/run.sh expiry             # A's check-in runs out; the room says so
#   scripts/e2e/run.sh push               # tap every push fixture's banner; check the screen
#   scripts/e2e/run.sh all                # every journey above, one after another
#
# Options:
#   --repeat N    run the journeys N times in a row, stopping at the first failure
#   --record      record both Simulators (Glow B shows person B's own app) to
#                 docs/shots/d1-e2e-<journey>-A.mp4 and -B.mp4 (scripts/e2e/record.sh also joins them)
#   --no-build    skip scripts/sim.sh build (the app is already built for this API)
#
# Each run makes a room of its own (harness.ts room) and ends it afterwards, and both people are
# fresh @glow.test addresses, so runs never see each other (D1-D1). If nothing answers on $GLOW_API
# it starts `pnpm dev` there itself, and stops it at the end. The server needs ALLOW_TEST_LOGIN
# (pnpm env:setup --force --test-login). Logs: .agent-state/e2e/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
E2E="$ROOT/scripts/e2e"
LOGS="$ROOT/.agent-state/e2e"
mkdir -p "$LOGS"

say() { printf '==> %s\n' "$*"; }
die() { printf 'e2e: %s\n' "$*" >&2; exit 1; }

JOURNEYS=()
REPEAT=1
RECORD=0
BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    full | chat | block | expiry | push) JOURNEYS+=("$1") ;;
    all) JOURNEYS+=(full chat block expiry push) ;;
    --repeat) REPEAT="${2:?--repeat needs a number}"; shift ;;
    --record) RECORD=1 ;;
    --no-build) BUILD=0 ;;
    -h | --help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown argument $1 (try --help)" ;;
  esac
  shift
done
[ "${#JOURNEYS[@]}" -gt 0 ] || die "which journey? full, chat, block, expiry, push or all (try --help)"

API="${GLOW_API:-http://localhost:3000}"
PORT_NUM="${PORT:-3000}"
CONTROL_PORT=$((PORT_NUM + 1000)) # player B's instructions
HARNESS_PORT=$((PORT_NUM + 1100)) # the Mac-side helper (pushes, expiry)
SIM_A="${GLOW_SIM_A:-Glow A}"
SIM_B="${GLOW_SIM_B:-Glow B}"
PHOTO_A="$ROOT/ios/fixtures/photos/outfit-real-white-suit.jpg"
PHOTO_B="$ROOT/ios/fixtures/photos/outfit-real-blue-flightsuit.jpg"
BUNDLE_ID="com.davidxie.glow"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Classes in ios/GlowUITests, one per journey.
class_of() {
  case "$1" in
    full) echo FullLoopJourneyTests ;;
    chat) echo ChatJourneyTests ;;
    block) echo BlockJourneyTests ;;
    expiry) echo ExpiryJourneyTests ;;
    push) echo PushTapUITests ;;
  esac
}

PIDS=()
SERVER_PID=""
cleanup() {
  local pid
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  # Recording boots both Simulators: give both slots back (at most 3 are booted on this Mac).
  if [ "$RECORD" -eq 1 ]; then scripts/sim.sh release >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

udid_of() {
  xcrun simctl list devices -j | node -e '
    let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const all = Object.values(JSON.parse(s).devices).flat();
      const d = all.find((x) => x.name === process.argv[1] && x.isAvailable);
      process.stdout.write(d ? d.udid : "");
    });' "$1"
}

json_field() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s)[process.argv[1]] ?? "")))' "$1"; }

wait_for_url() { # <url> <seconds>
  local i=0
  until curl -s -o /dev/null --max-time 2 "$1"; do
    i=$((i + 1))
    [ "$i" -lt "$2" ] || return 1
    sleep 1
  done
}

# --- The server ------------------------------------------------------------------------------

if ! curl -s -o /dev/null --max-time 3 "$API/api/me"; then
  say "Nothing on $API: starting pnpm dev on port $PORT_NUM (log: .agent-state/e2e/server.log)"
  PORT="$PORT_NUM" pnpm dev >"$LOGS/server.log" 2>&1 &
  SERVER_PID=$!
  wait_for_url "$API/api/me" 90 || die "the server didn't start. See .agent-state/e2e/server.log"
fi
probe="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/dev/test-login" \
  -H 'content-type: application/json' -H "x-forwarded-for: 10.$((RANDOM % 250)).$((RANDOM % 250)).7" --data '{}')"
# A bad body answers 400 when test sign-in is on (it checks the body first); 404 when it's off.
case "$probe" in
  400 | 401 | 422 | 429) ;;
  *) die "test sign-in answered $probe on $API. Run pnpm env:setup --force --test-login, then restart the server." ;;
esac

# --- The app ---------------------------------------------------------------------------------

if [ "$BUILD" -eq 1 ]; then scripts/sim.sh build; fi

prepare_simulators() {
  if [ "$RECORD" -eq 1 ]; then scripts/sim.sh setup; else scripts/sim.sh setup A; fi
  UDID_A="$(udid_of "$SIM_A")"
  [ -n "$UDID_A" ] || die "no Simulator named $SIM_A"
  scripts/sim.sh at venue A >/dev/null
  # `simctl privacy` needs the app installed, which a new or erased Simulator doesn't have yet: the
  # grant used to do nothing there, and iOS's location dialog covered the Join screen on run 1
  # (D1-D8). So install first, every run, then grant, and fail loudly if either can't be done.
  scripts/sim.sh install A >/dev/null || die "could not install Glow on $SIM_A (build it first, or drop --no-build)"
  xcrun simctl privacy "$UDID_A" grant location "$BUNDLE_ID" || die "could not grant location to Glow on $SIM_A"
}

# --- One journey ------------------------------------------------------------------------------

run_journey() { # <journey> <run number>
  local journey="$1" n="$2" class log room room_id slug token link a email_a id_a token_a
  class="$(class_of "$journey")"
  log="$LOGS/$journey-$n"
  say "Journey $journey, run $n: $class on $SIM_A"
  prepare_simulators
  if [ "$journey" = push ]; then scripts/sim.sh allow-push A >/dev/null; fi

  room="$(node "$E2E/harness.ts" room)"
  room_id="$(printf '%s' "$room" | json_field id)"
  slug="$(printf '%s' "$room" | json_field slug)"
  token="$(printf '%s' "$room" | json_field token)"
  link="$(printf '%s' "$room" | json_field link)"
  a="$(node "$E2E/harness.ts" person a --name Avery --gender woman --show-me man)"
  email_a="$(printf '%s' "$a" | json_field email)"
  id_a="$(printf '%s' "$a" | json_field userId)"
  token_a="$(printf '%s' "$a" | json_field accessToken)"

  node "$E2E/harness.ts" serve --port "$HARNESS_PORT" --udid "$UDID_A" --token "$token_a" \
    --room "$room_id" >"$log-harness.log" 2>&1 &
  PIDS+=($!)

  local b_pid="" email_b=""
  if [ "$journey" != push ]; then
    email_b="b-$(node -e 'process.stdout.write(crypto.randomUUID().slice(0, 8))')@glow.test"
    node "$E2E/player-b.ts" --api "$API" --slug "$slug" --token "$token" --email "$email_b" \
      --photo "$PHOTO_B" --control "$CONTROL_PORT" --watch-user "$id_a" --watch-name Avery \
      >"$log-player-b.jsonl" 2>"$log-player-b.log" &
    b_pid=$!
    PIDS+=("$b_pid")
    # Ready once B has checked in: its first card is in the room before A arrives.
    local i=0
    until curl -s --max-time 2 "http://127.0.0.1:$CONTROL_PORT/state" | grep -q '"step":"checked-in"'; do
      i=$((i + 1))
      if [ "$i" -gt 60 ] || ! kill -0 "$b_pid" 2>/dev/null; then
        cat "$log-player-b.log" >&2
        die "player B didn't get checked in (log: ${log#"$ROOT/"}-player-b.log)"
      fi
      sleep 1
    done
  fi
  wait_for_url "http://127.0.0.1:$HARNESS_PORT/health" 20 || die "the harness didn't start"

  local rec_pid=""
  if [ "$RECORD" -eq 1 ] && [ -n "$email_b" ]; then
    # Glow B shows person B's own app, signed in as the same test person player B plays.
    local udid_b
    udid_b="$(udid_of "$SIM_B")"
    scripts/sim.sh install B >/dev/null
    xcrun simctl launch --terminate-running-process "$udid_b" com.davidxie.glow \
      -GlowDebugTestLogin "$email_b" >/dev/null
    scripts/sim.sh record "d1-e2e-$journey" >"$log-record.log" 2>&1 &
    rec_pid=$!
  fi

  local code=0
  TEST_RUNNER_GLOW_E2E_PLAYER_B="http://127.0.0.1:$CONTROL_PORT" \
    TEST_RUNNER_GLOW_E2E_HARNESS="http://127.0.0.1:$HARNESS_PORT" \
    TEST_RUNNER_GLOW_E2E_EMAIL_A="$email_a" \
    TEST_RUNNER_GLOW_E2E_ROOM_LINK="$link" \
    TEST_RUNNER_GLOW_E2E_PHOTO="$PHOTO_A" \
    TEST_RUNNER_GLOW_E2E_PUSH_DIR="$ROOT/ios/fixtures/push" \
    scripts/sim.sh test "GlowUITests/$class" || code=$?

  if [ -n "$rec_pid" ]; then kill -TERM "$rec_pid" 2>/dev/null || true; wait "$rec_pid" 2>/dev/null || true; fi
  if [ -n "$b_pid" ]; then
    curl -s -X POST --max-time 5 "http://127.0.0.1:$CONTROL_PORT/quit" >/dev/null || true
    local b_code=0
    wait "$b_pid" || b_code=$?
    if [ "$b_code" -ne 0 ]; then
      say "Player B reported a failure (exit $b_code): ${log#"$ROOT/"}-player-b.log"
      [ "$code" -ne 0 ] || code="$b_code"
    fi
  fi
  curl -s -X POST --max-time 5 "http://127.0.0.1:$HARNESS_PORT/quit" >/dev/null || true
  node "$E2E/harness.ts" end-room "$room_id" >/dev/null || true
  return "$code"
}

started=$(date +%s)
passed=0
for n in $(seq 1 "$REPEAT"); do
  for journey in "${JOURNEYS[@]}"; do
    if ! run_journey "$journey" "$n"; then
      say "FAILED: $journey on run $n of $REPEAT, after $passed passed. Logs: .agent-state/e2e/"
      exit 1
    fi
    passed=$((passed + 1))
  done
done
say "e2e ${JOURNEYS[*]}: $passed of $passed passed ($REPEAT in a row), $(($(date +%s) - started))s"

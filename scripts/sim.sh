#!/usr/bin/env bash
# Glow Simulator workflow. Built by A3; owned by A1 from Wave 1. See docs/SPEC.md "Simulator
# workflow" and docs/HANDOFFS.md.
#
# Two Simulators, Glow A and Glow B, so one Mac can play both people in a match.
# Run `scripts/sim.sh help` for every command. Works with macOS's bash 3.2.
#
# Parallel agents on one Mac: `eval "$(scripts/agent-env.sh <ID>)"` first. It sets
#   GLOW_SIM_A, GLOW_SIM_B     this agent's Simulator names (default "Glow A" and "Glow B")
#   GLOW_API_BASE_URL          the API the Debug app talks to (default http://localhost:3000)
#   GLOW_SUPABASE_URL, GLOW_SUPABASE_ANON_KEY   with --own-db, the agent's own Supabase

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS="$ROOT/ios"
BUILD="$IOS/build"
DERIVED="$BUILD/DerivedData"
PACKAGES="$BUILD/SourcePackages"
LOGS="$BUILD/logs"
SHOTS="$ROOT/docs/shots"
PROJECT="$IOS/Glow.xcodeproj"
SCHEME="Glow"
BUNDLE_ID="com.davidxie.glow"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Glow.app"
LOCKFILE="$IOS/Package.resolved"
PROJECT_LOCKFILE="$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
SIM_A="${GLOW_SIM_A:-Glow A}"
SIM_B="${GLOW_SIM_B:-Glow B}"
[ "$SIM_A" != "$SIM_B" ] || { printf 'sim.sh: GLOW_SIM_A and GLOW_SIM_B must differ\n' >&2; exit 1; }

# shellcheck source=../ios/fixtures/demo-room.env
source "$IOS/fixtures/demo-room.env"

say() { printf '==> %s\n' "$*"; }
die() { printf 'sim.sh: %s\n' "$*" >&2; exit 1; }

# --- Toolchain -------------------------------------------------------------------------------

# Use the full Xcode even when xcode-select points at the Command Line Tools.
use_xcode() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then return; fi
  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [ -z "$selected" ] || [ ! -d "$selected/Platforms/iPhoneSimulator.platform" ]; then
    if [ -d /Applications/Xcode.app/Contents/Developer ]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
      die "no full Xcode found. Install Xcode, or set DEVELOPER_DIR."
    fi
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing. $2"
}

# --- Simulators ------------------------------------------------------------------------------

# Prints the UDID of the named Simulator, or nothing.
udid_of() {
  xcrun simctl list -j devices available |
    jq -r --arg name "$1" '[.devices[][] | select(.name == $name)] | first | .udid // empty'
}

udid_or_die() {
  local udid
  udid="$(udid_of "$1")"
  [ -n "$udid" ] || die "$1 doesn't exist yet. Run: scripts/sim.sh setup"
  touch_slot "$udid"
  printf '%s' "$udid"
}

# Expands A, B or both (the default) into Simulator names, one per line.
targets() {
  case "${1:-both}" in
    A | a) echo "$SIM_A" ;;
    B | b) echo "$SIM_B" ;;
    both | all) printf '%s\n%s\n' "$SIM_A" "$SIM_B" ;;
    *) die "unknown Simulator '$1'. Use A, B or both." ;;
  esac
}

# A or B, for a Simulator name from targets().
letter_of() {
  if [ "$1" = "$SIM_A" ]; then echo A; else echo B; fi
}

newest_runtime() {
  xcrun simctl list -j runtimes available |
    jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
}

# The newest "iPhone NN Pro" (not Max) the runtime supports.
newest_pro_device_type() {
  xcrun simctl list -j runtimes available |
    jq -r --arg runtime "$1" '.runtimes[] | select(.identifier == $runtime) | .supportedDeviceTypes[]
      | select(.name | test("^iPhone [0-9]+ Pro$")) | .identifier' |
    sort -V | tail -1
}

# --- Simulator slots ---------------------------------------------------------------------------
# At most GLOW_SIM_MAX_SLOTS (3) Glow Simulators are booted on this Mac at once, across every
# agent. A slot is a directory under GLOW_SIM_SLOT_DIR, taken with an atomic mkdir. Its `owner`
# file names the Simulator, the agent, the time, and (from ci-local) the owning process. A slot
# is stale, and reclaimed, when its owning process is gone (its Simulator is shut down too), or
# when its Simulator isn't booted any more, after a grace period for booting.
SLOT_DIR="${GLOW_SIM_SLOT_DIR:-/tmp/glow-sim-slots}"
MAX_SLOTS="${GLOW_SIM_MAX_SLOTS:-3}"
SLOT_WAIT="${GLOW_SIM_SLOT_WAIT:-1800}"
SLOT_GRACE=180
# A slot nobody has used through sim.sh for this long is freed and its Simulator shut down, in
# case its owner stopped without cleaning up (several agents can share one owner process).
SLOT_IDLE="${GLOW_SIM_SLOT_IDLE:-7200}"
RELEASE_ON_EXIT=""

# At most GLOW_MAX_BUILDS (4) xcodebuild runs (build, test, allow-push) at once on this Mac,
# across every agent: parallel builds are what pushed the load average toward 870. Same mechanism
# as the Simulator slots, in GLOW_BUILD_SLOT_DIR. A build slot belongs to the sim.sh process that
# runs xcodebuild, and is freed when that process exits, however it exits.
BUILD_SLOT_DIR="${GLOW_BUILD_SLOT_DIR:-/tmp/glow-build-slots}"
MAX_BUILDS="${GLOW_MAX_BUILDS:-4}"
BUILD_WAIT="${GLOW_BUILD_SLOT_WAIT:-3600}"
BUILD_SLOT=""

booted_glow_udids() {
  xcrun simctl list -j devices booted | jq -r '.devices[][] | select(.name | startswith("Glow")) | .udid'
}

slot_field() { # <slot dir> <key>
  sed -nE "s/^$2=//p" "$1/owner" 2>/dev/null | head -1
}

slot_of() { # <udid>: prints the slot holding it
  local slot
  for slot in "$SLOT_DIR"/slot-*; do
    if [ -d "$slot" ] && [ "$(slot_field "$slot" udid)" = "$1" ]; then
      echo "$slot"
      return 0
    fi
  done
  return 1
}

slot_field_gone() { # a readable name for a Simulator whose slot is already gone
  xcrun simctl list -j devices | jq -r --arg u "$1" '[.devices[][] | select(.udid == $u) | .name] | first // "its Simulator"'
}

# Marks a slot as just used, so an active Simulator never counts as idle.
touch_slot() {
  local held
  if held="$(slot_of "$1")"; then sed -i '' "s/^since=.*/since=$(date +%s)/" "$held/owner" 2>/dev/null || true; fi
}

reap_slots() {
  local booted slot udid pid since now
  booted="$(booted_glow_udids 2>/dev/null || true)"
  now="$(date +%s)"
  for slot in "$SLOT_DIR"/slot-*; do
    [ -d "$slot" ] || continue
    udid="$(slot_field "$slot" udid)"
    pid="$(slot_field "$slot" pid)"
    since="$(slot_field "$slot" since)"
    if [ -n "$pid" ] && [ "$pid" != 0 ] && ! kill -0 "$pid" 2>/dev/null; then
      if [ -n "$udid" ]; then xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; fi
      rm -rf "$slot"
      say "Freed $(basename "$slot"): its owner (process $pid) is gone, so $(slot_field_gone "$udid") was shut down."
    elif [ $((now - ${since:-0})) -gt "$SLOT_IDLE" ]; then
      if [ -n "$udid" ]; then xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; fi
      rm -rf "$slot"
      say "Freed $(basename "$slot"): unused for over $((SLOT_IDLE / 60)) minutes, so its Simulator was shut down."
    elif [ $((now - ${since:-0})) -gt "$SLOT_GRACE" ] && ! printf '%s\n' "$booted" | grep -qx "$udid"; then
      rm -rf "$slot"
    fi
  done
}

show_slots() {
  local slot since any=0
  for slot in "$SLOT_DIR"/slot-*; do
    [ -d "$slot" ] || continue
    any=1
    since="$(slot_field "$slot" since)"
    printf '    %s: %s (agent %s, process %s, since %s)\n' "$(basename "$slot")" "$(slot_field "$slot" name)" \
      "$(slot_field "$slot" agent)" "$(slot_field "$slot" pid)" "$(date -r "${since:-0}" +%H:%M:%S 2>/dev/null || echo '?')" >&2
  done
  local unslotted
  unslotted="$(unslotted_glow_booted "")"
  if [ "$unslotted" -gt 0 ]; then printf '    plus %s Glow Simulator(s) booted outside sim.sh\n' "$unslotted" >&2; fi
  if [ "$any" -eq 0 ] && [ "$unslotted" -eq 0 ]; then printf '    all free\n' >&2; fi
}

# Booted Glow Simulators that hold no slot (booted outside sim.sh) count too. $1 is left out.
unslotted_glow_booted() {
  local udid count=0
  while IFS= read -r udid; do
    [ -n "$udid" ] && [ "$udid" != "$1" ] || continue
    slot_of "$udid" >/dev/null || count=$((count + 1))
  done < <(booted_glow_udids 2>/dev/null || true)
  echo "$count"
}

# The process that owns a slot: GLOW_SLOT_OWNER_PID if set (ci-local sets it to itself), else
# the nearest ancestor that isn't a shell, which for an agent is the agent's own long-lived
# process and for a person is their terminal. When it dies (an outage, a crash), the slot is
# freed and its Simulator shut down.
owner_pid() {
  if [ -n "${GLOW_SLOT_OWNER_PID:-}" ]; then
    echo "$GLOW_SLOT_OWNER_PID"
    return
  fi
  local pid="$PPID" comm i
  for i in 1 2 3 4 5 6 7 8; do
    comm="$(ps -o comm= -p "$pid" 2>/dev/null | sed 's#.*/##; s/^-//')"
    case "$comm" in
      bash | zsh | sh | dash | fish | env | sudo | timeout | "") ;;
      *)
        echo "$pid"
        return
        ;;
    esac
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [ -z "$pid" ] || [ "$pid" -le 1 ]; then break; fi
  done
  echo 0
}

# Takes a slot for <udid> <name>, waiting (a local sleep, no network) until one is free.
acquire_slot() {
  local udid="$1" name="$2" waited=0 i slot used held
  mkdir -p "$SLOT_DIR"
  chmod 1777 "$SLOT_DIR" 2>/dev/null || true
  if held="$(slot_of "$udid")"; then
    # Already ours (say, setup then test): make the current process its owner, so an owner
    # that died earlier doesn't get the Simulator shut down under us.
    sed -i '' -e "s/^pid=.*/pid=$(owner_pid)/" -e "s/^since=.*/since=$(date +%s)/" "$held/owner" 2>/dev/null || true
    return 0
  fi
  while :; do
    reap_slots
    used="$(find "$SLOT_DIR" -maxdepth 1 -name 'slot-*' -type d | wc -l | tr -d ' ')"
    used=$((used + $(unslotted_glow_booted "$udid")))
    if [ "$used" -lt "$MAX_SLOTS" ]; then
      for i in $(seq 1 "$MAX_SLOTS"); do
        slot="$SLOT_DIR/slot-$i"
        if mkdir "$slot" 2>/dev/null; then
          printf 'udid=%s\nname=%s\nagent=%s\npid=%s\nsince=%s\n' "$udid" "$name" "${GLOW_AGENT_ID:-none}" \
            "$(owner_pid)" "$(date +%s)" >"$slot/owner"
          return 0
        fi
      done
    fi
    if [ $((waited % 60)) -eq 0 ]; then
      say "All $MAX_SLOTS Simulator slots on this Mac are taken (waited ${waited}s). Holders:"
      show_slots
    fi
    [ "$waited" -lt "$SLOT_WAIT" ] || die "no Simulator slot came free in ${SLOT_WAIT}s."
    sleep 10
    waited=$((waited + 10))
  done
}

# Shuts the Simulator down and frees its slot.
release_slot() {
  local slot
  xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  if slot="$(slot_of "$1")"; then rm -rf "$slot"; fi
}

release_on_exit() {
  if [ -n "$RELEASE_ON_EXIT" ]; then
    release_slot "$RELEASE_ON_EXIT"
    say "Shut down $SIM_A and freed its Simulator slot."
  fi
}

reap_build_slots() {
  local slot pid
  for slot in "$BUILD_SLOT_DIR"/slot-*; do
    [ -d "$slot" ] || continue
    pid="$(slot_field "$slot" pid)"
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then rm -rf "$slot"; fi
  done
}

show_build_slots() {
  local slot since
  for slot in "$BUILD_SLOT_DIR"/slot-*; do
    [ -d "$slot" ] || continue
    since="$(slot_field "$slot" since)"
    printf '    %s: %s for agent %s (process %s, since %s)\n' "$(basename "$slot")" "$(slot_field "$slot" what)" \
      "$(slot_field "$slot" agent)" "$(slot_field "$slot" pid)" "$(date -r "${since:-0}" +%H:%M:%S 2>/dev/null || echo '?')" >&2
  done
}

# Waits (a local sleep, no network) for one of the Mac's build slots, for `xcodebuild <what>`.
acquire_build_slot() {
  local what="$1" waited=0 i slot
  [ -z "$BUILD_SLOT" ] || return 0
  mkdir -p "$BUILD_SLOT_DIR"
  chmod 1777 "$BUILD_SLOT_DIR" 2>/dev/null || true
  while :; do
    reap_build_slots
    for i in $(seq 1 "$MAX_BUILDS"); do
      slot="$BUILD_SLOT_DIR/slot-$i"
      if mkdir "$slot" 2>/dev/null; then
        printf 'what=%s\nagent=%s\npid=%s\nsince=%s\n' "$what" "${GLOW_AGENT_ID:-none}" "$$" "$(date +%s)" >"$slot/owner"
        BUILD_SLOT="$slot"
        return 0
      fi
    done
    if [ $((waited % 60)) -eq 0 ]; then
      say "All $MAX_BUILDS build slots on this Mac are busy (waited ${waited}s). Holders:"
      show_build_slots
    fi
    [ "$waited" -lt "$BUILD_WAIT" ] || die "no build slot came free in ${BUILD_WAIT}s."
    sleep 10
    waited=$((waited + 10))
  done
}

release_build_slot() {
  if [ -n "$BUILD_SLOT" ]; then
    rm -rf "$BUILD_SLOT"
    BUILD_SLOT=""
  fi
}

# Whatever happens, give back what this run holds.
on_exit() {
  release_build_slot
  release_on_exit
}
trap on_exit EXIT

boot() { # <udid> [name]: takes a slot first, so at most MAX_SLOTS are ever booted
  local udid="$1" name="${2:-$1}"
  acquire_slot "$udid" "$name"
  if ! booted_glow_udids 2>/dev/null | grep -qx "$udid"; then say "Booting $name ($udid)"; fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

cmd_setup() {
  use_xcode
  need jq "Install it with: brew install jq"
  local runtime device_type
  runtime="$(newest_runtime)"
  [ -n "$runtime" ] || die "no iOS Simulator runtime installed. Add one in Xcode > Settings > Components."
  device_type="$(newest_pro_device_type "$runtime")"
  [ -n "$device_type" ] || die "the runtime $runtime has no iPhone Pro device type."

  local name udid
  while IFS= read -r name; do
    udid="$(udid_of "$name")"
    if [ -z "$udid" ]; then
      say "Creating $name (${device_type##*.}, ${runtime##*.})"
      udid="$(xcrun simctl create "$name" "$device_type" "$runtime")"
    fi
    boot "$udid" "$name"
    xcrun simctl ui "$udid" appearance dark >/dev/null 2>&1 || true
    xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
      --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
    say "$name is ready."
  done < <(targets "${1:-both}")
  if ! on_ci; then open -a Simulator; fi
}

# Shuts down and deletes this agent's Simulators. The shared default names need --yes.
cmd_teardown() {
  use_xcode
  need jq "Install it with: brew install jq"
  local which="both" yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      --yes) yes=1 ;;
      *) which="$arg" ;;
    esac
  done
  if [ -z "${GLOW_SIM_A:-}${GLOW_SIM_B:-}" ] && [ "$yes" -ne 1 ]; then
    die "teardown would delete the shared default Simulators \"$SIM_A\" and \"$SIM_B\". Set GLOW_SIM_A and GLOW_SIM_B (scripts/agent-env.sh), or pass --yes."
  fi
  local name udid
  while IFS= read -r name; do
    udid="$(udid_of "$name")"
    if [ -z "$udid" ]; then
      say "$name doesn't exist. Nothing to do."
      continue
    fi
    release_slot "$udid"
    xcrun simctl delete "$udid"
    say "Deleted $name ($udid)"
  done < <(targets "$which")
}

# Shuts down this agent's Simulators and frees their slots, without deleting them.
cmd_release() {
  use_xcode
  need jq "Install it with: brew install jq"
  local name udid
  while IFS= read -r name; do
    udid="$(udid_of "$name")"
    [ -n "$udid" ] || continue
    release_slot "$udid"
    say "Shut down $name and freed its slot."
  done < <(targets "${1:-both}")
}

cmd_slots() {
  use_xcode
  need jq "Install it with: brew install jq"
  mkdir -p "$SLOT_DIR" "$BUILD_SLOT_DIR"
  reap_slots
  reap_build_slots
  say "Simulator slots ($MAX_SLOTS on this Mac, in $SLOT_DIR):"
  show_slots
  say "Build slots ($MAX_BUILDS on this Mac, in $BUILD_SLOT_DIR):"
  if [ -n "$(find "$BUILD_SLOT_DIR" -maxdepth 1 -name 'slot-*' -type d)" ]; then show_build_slots; else printf '    all free\n' >&2; fi
}

# --- Build -----------------------------------------------------------------------------------

generate() {
  need xcodegen "Install it with: brew install xcodegen"
  (cd "$IOS" && xcodegen generate --spec project.yml --quiet)
}

destination() {
  local udid
  udid="$(udid_of "$SIM_A")"
  if [ -n "$udid" ]; then echo "id=$udid"; else echo "generic/platform=iOS Simulator"; fi
}

on_ci() {
  [ -n "${GLOW_CI:-}" ] || [ -n "${CI:-}" ]
}

xcodebuild_glow() {
  local extra=()
  if on_ci; then
    # Headless and unattended: no signing, exactly the committed package versions, no prompts
    # to trust package plugins or macros.
    extra=(CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -skipMacroValidation)
    if [ -f "$LOCKFILE" ]; then extra+=(-onlyUsePackageVersionsFromResolvedFile); fi
  fi
  # Per-agent endpoints (scripts/agent-env.sh). Command-line settings win over the xcconfig.
  if [ -n "${GLOW_API_BASE_URL:-}" ]; then extra+=("API_BASE_URL=$GLOW_API_BASE_URL"); fi
  if [ -n "${GLOW_SUPABASE_URL:-}" ]; then extra+=("SUPABASE_URL=$GLOW_SUPABASE_URL"); fi
  if [ -n "${GLOW_SUPABASE_ANON_KEY:-}" ]; then extra+=("SUPABASE_ANON_KEY=$GLOW_SUPABASE_ANON_KEY"); fi
  # The last argument is the action (build or test), for the build slot's label.
  local what="${!#}" code=0
  acquire_build_slot "$what"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" ${extra[@]+"${extra[@]}"} "$@" || code=$?
  release_build_slot
  return "$code"
}

# Keeps ios/Package.resolved in step with what Xcode resolved. Xcode reads the lockfile from the
# generated workspace (project.yml's postGenCommand copies it in), but writes a first resolution
# into the local package's folder when the workspace has none.
sync_lockfile() {
  local resolved=""
  if [ -f "$PROJECT_LOCKFILE" ]; then
    resolved="$PROJECT_LOCKFILE"
  elif [ -f "$IOS/Packages/GlowKit/Package.resolved" ]; then
    resolved="$IOS/Packages/GlowKit/Package.resolved"
  fi
  if [ -n "$resolved" ] && ! cmp -s "$resolved" "$LOCKFILE"; then
    cp "$resolved" "$LOCKFILE"
    say "Updated ios/Package.resolved. Commit it with the dependency change."
  fi
}

cmd_build() {
  use_xcode
  need jq "Install it with: brew install jq"
  mkdir -p "$LOGS"
  say "Generating Glow.xcodeproj from ios/project.yml"
  generate
  say "Building Debug for the Simulator against ${GLOW_API_BASE_URL:-http://localhost:3000} (log: ios/build/logs/build.log)"
  acquire_build_slot build # here, so waiting shows in the terminal, not in the log
  if ! xcodebuild_glow -destination "$(destination)" build >"$LOGS/build.log" 2>&1; then
    grep -E "error:|warning:|BUILD FAILED" "$LOGS/build.log" | sort -u | head -40 >&2 || true
    die "build failed. Full log: ios/build/logs/build.log"
  fi
  sync_lockfile
  say "Built $APP"
}

# --- Run -------------------------------------------------------------------------------------

cmd_install() {
  use_xcode
  [ -d "$APP" ] || die "no build yet. Run: scripts/sim.sh build"
  local name udid
  while IFS= read -r name; do
    udid="$(udid_or_die "$name")"
    boot "$udid" "$name"
    say "Installing on $name"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
  done < <(targets "${1:-both}")
}

cmd_launch() {
  use_xcode
  local name udid
  while IFS= read -r name; do
    udid="$(udid_or_die "$name")"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
    say "Launched Glow on $name"
  done < <(targets "${1:-both}")
}

cmd_at() {
  use_xcode
  local place="${1:-}" lat lng
  case "$place" in
    venue)
      lat="$GLOW_DEMO_LAT"
      lng="$GLOW_DEMO_LNG"
      ;;
    away)
      # 2 km north of the room's center: 2000 m / 111,320 m per degree of latitude.
      lat="$(awk -v lat="$GLOW_DEMO_LAT" 'BEGIN { printf "%.6f", lat + 2000 / 111320 }')"
      lng="$GLOW_DEMO_LNG"
      ;;
    *) die "usage: scripts/sim.sh at venue|away [A|B|both]" ;;
  esac
  local name
  while IFS= read -r name; do
    xcrun simctl location "$(udid_or_die "$name")" set "$lat,$lng"
    say "Moved $name to $place"
  done < <(targets "${2:-both}")
}

cmd_photos() {
  use_xcode
  local name
  while IFS= read -r name; do
    xcrun simctl addmedia "$(udid_or_die "$name")" "$IOS"/fixtures/photos/*.jpg
    say "Added fixture photos to $name"
  done < <(targets "${1:-both}")
}

open_url() {
  local url="$1" name
  while IFS= read -r name; do
    xcrun simctl openurl "$(udid_or_die "$name")" "$url"
    say "Opened the link on $name"
  done < <(targets "${2:-both}")
}

cmd_scan() {
  use_xcode
  local slug="${1:-}"
  [ -n "$slug" ] || die "usage: scripts/sim.sh scan <slug> [A|B|both]"
  local token="${TOKEN:-}"
  if [ -z "$token" ] && [ "$slug" = "$GLOW_DEMO_SLUG" ]; then token="$GLOW_DEMO_TOKEN"; fi
  local url="glow://r/$slug"
  if [ -n "$token" ]; then url="$url?t=$token"; fi
  # The iPhone camera hands a room's universal link straight to Glow. simctl openurl can't do that
  # here (no live domain, and iOS asks "Open in Glow?" for glow:// links), so relaunch the Debug app
  # with the link instead: it goes through the same Router.open as a real link.
  # `scripts/sim.sh open <url>` takes the system path, prompt and all.
  local name udid
  while IFS= read -r name; do
    udid="$(udid_or_die "$name")"
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -GlowDebugOpenURL "$url" >/dev/null
    say "Opened $url on $name"
  done < <(targets "${2:-both}")
}

cmd_open() {
  use_xcode
  [ -n "${1:-}" ] || die "usage: scripts/sim.sh open <url> [A|B|both]"
  open_url "$1" "${2:-both}"
}

cmd_push() {
  use_xcode
  local who="${1:-}" event="${2:-}"
  [ -n "$who" ] && [ -n "$event" ] || die "usage: scripts/sim.sh push A|B|both <event>, for example: push A match_created"
  event="$(printf '%s' "$event" | tr '.' '_')"
  local payload="$IOS/fixtures/push/$event.apns"
  [ -f "$payload" ] || die "no fixture at ios/fixtures/push/$event.apns. Fixtures: $(cd "$IOS/fixtures/push" && ls ./*.apns | sed 's|./||; s|.apns||' | tr '\n' ' ')"
  local name
  while IFS= read -r name; do
    xcrun simctl push "$(udid_or_die "$name")" "$BUNDLE_ID" "$payload"
    say "Sent $event to $name. No banner? Run once: scripts/sim.sh allow-push $who"
  done < <(targets "$who")
}

# simctl can't grant notification permission, so a UI test launches Glow, asks, and taps Allow.
cmd_allow_push() {
  use_xcode
  generate
  mkdir -p "$LOGS"
  local name udid
  while IFS= read -r name; do
    udid="$(udid_or_die "$name")"
    boot "$udid" "$name"
    say "Granting notification permission on $name (log: ios/build/logs/allow-push.log)"
    acquire_build_slot allow-push
    if ! xcodebuild_glow -destination "id=$udid" \
      -only-testing:GlowUITests/SimulatorSetupUITests/testAllowNotifications test >"$LOGS/allow-push.log" 2>&1; then
      tail -20 "$LOGS/allow-push.log" >&2
      die "couldn't grant permission on $name."
    fi
  done < <(targets "${1:-both}")
}

# --- Capture ---------------------------------------------------------------------------------

cmd_shot() {
  use_xcode
  local shot="${1:-}"
  [ -n "$shot" ] || die "usage: scripts/sim.sh shot <name> [A|B|both]"
  mkdir -p "$SHOTS"
  local name letter
  while IFS= read -r name; do
    letter="$(letter_of "$name")"
    xcrun simctl io "$(udid_or_die "$name")" screenshot --type=png "$SHOTS/$shot-$letter.png" >/dev/null 2>&1
    say "Saved docs/shots/$shot-$letter.png"
  done < <(targets "${2:-both}")
}

cmd_record() {
  use_xcode
  local clip="${1:-recording-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$SHOTS"
  local udid_a udid_b
  udid_a="$(udid_or_die "$SIM_A")"
  udid_b="$(udid_or_die "$SIM_B")"
  xcrun simctl io "$udid_a" recordVideo --codec=h264 --force "$SHOTS/$clip-A.mp4" &
  local pid_a=$!
  xcrun simctl io "$udid_b" recordVideo --codec=h264 --force "$SHOTS/$clip-B.mp4" &
  local pid_b=$!
  # Ctrl-C (or `kill <pid>`, since background jobs ignore SIGINT) stops both recorders cleanly.
  trap 'kill -INT $pid_a $pid_b 2>/dev/null || true' INT TERM
  local seconds="${2:-}"
  if [ -n "$seconds" ]; then
    say "Recording both screens for $seconds seconds."
    sleep "$seconds"
    kill -INT $pid_a $pid_b 2>/dev/null || true
  else
    say "Recording both screens. Press Ctrl-C to stop."
  fi
  wait $pid_a $pid_b 2>/dev/null || true
  trap - INT TERM
  say "Saved docs/shots/$clip-A.mp4 and docs/shots/$clip-B.mp4"
}

# --- Test and lint ---------------------------------------------------------------------------

cmd_test() {
  use_xcode
  need jq "Install it with: brew install jq"
  mkdir -p "$LOGS"
  generate
  local udid only=()
  udid="$(udid_or_die "$SIM_A")"
  # xcodebuild would boot Glow A itself, so take its slot first, and give it back when done.
  boot "$udid" "$SIM_A"
  RELEASE_ON_EXIT="$udid"
  case "${1:-}" in
    "") ;;
    unit) only=(-skip-testing:GlowUITests) ;;
    ui | GlowUITests) only=(-only-testing:GlowUITests) ;;
    Glow | GlowTests | app) only=(-only-testing:GlowTests) ;;
    *Tests) only=("-only-testing:$1") ;;
    *) only=("-only-testing:${1}Tests") ;;
  esac
  say "Testing on $SIM_A ${1:+($1) }(log: ios/build/logs/test.log)"
  local results="$BUILD/results/test-$(date +%Y%m%d-%H%M%S).xcresult"
  mkdir -p "$BUILD/results"
  acquire_build_slot test
  if ! xcodebuild_glow -destination "id=$udid" -resultBundlePath "$results" ${only[@]+"${only[@]}"} test >"$LOGS/test.log" 2>&1; then
    grep -E "error:|failed|Failing tests|✘|TEST FAILED" "$LOGS/test.log" | sort -u | head -40 >&2 || true
    die "tests failed. Full log: ios/build/logs/test.log"
  fi
  grep -E "Test run with|Executed [0-9]+ tests?|TEST SUCCEEDED" "$LOGS/test.log" | tail -4 || true
  sync_lockfile
}

cmd_lint() {
  use_xcode # SwiftLint needs the full Xcode's SourceKit
  need swiftlint "Install it with: brew install swiftlint"
  need swiftformat "Install it with: brew install swiftformat"
  # Explicit config and paths: a worktree lives under the main checkout's .claude/, and
  # SwiftFormat would otherwise also apply the parent checkout's .swiftformat and skip every
  # file. Both tools must report the files they checked, or the lint counts as failed.
  local out checked
  say "SwiftFormat"
  out="$(cd "$ROOT" && swiftformat --lint --config "$ROOT/.swiftformat" "$IOS" 2>&1)" || {
    printf '%s\n' "$out" >&2
    die "SwiftFormat found files to format. Run: swiftformat --config .swiftformat ios"
  }
  checked="$(printf '%s\n' "$out" | sed -nE 's|^(.* )?([0-9]+)/([0-9]+) files? require formatting.*|\3|p' | tail -1)"
  [ -n "$checked" ] && [ "$checked" -gt 0 ] || {
    printf '%s\n' "$out" >&2
    die "SwiftFormat checked no files, so the lint proves nothing."
  }
  say "SwiftFormat checked $checked files."
  say "SwiftLint"
  out="$(cd "$ROOT" && swiftlint lint --strict --config "$ROOT/.swiftlint.yml" 2>&1)" || {
    printf '%s\n' "$out" | grep -vE '^Linting ' >&2
    die "SwiftLint found violations."
  }
  checked="$(printf '%s\n' "$out" | sed -nE 's|^Done linting!.* in ([0-9]+) files?\.$|\1|p' | tail -1)"
  [ -n "$checked" ] && [ "$checked" -gt 0 ] || {
    printf '%s\n' "$out" >&2
    die "SwiftLint checked no files, so the lint proves nothing."
  }
  say "SwiftLint checked $checked files."
  say "Lint passed."
}

# Generates the project twice and checks both runs match, and that no .xcodeproj is in git.
cmd_verify_project() {
  generate
  local first
  first="$(mktemp -d)"
  cp -R "$PROJECT/project.pbxproj" "$PROJECT/xcshareddata" "$first/"
  generate
  if ! diff -r "$first/project.pbxproj" "$PROJECT/project.pbxproj" >/dev/null ||
    ! diff -r "$first/xcshareddata/xcschemes" "$PROJECT/xcshareddata/xcschemes" >/dev/null; then
    rm -rf "$first"
    die "xcodegen gave a different project the second time."
  fi
  rm -rf "$first"
  if git -C "$ROOT" ls-files | grep -q '\.xcodeproj/'; then
    die "a .xcodeproj is committed. Remove it from git: it's generated from ios/project.yml."
  fi
  say "xcodegen is deterministic, and no .xcodeproj is in git."
}

# --- Housekeeping ----------------------------------------------------------------------------

cmd_logs() {
  use_xcode
  xcrun simctl spawn "$(udid_or_die "$(targets "${1:-A}" | head -1)")" log stream --level debug \
    --predicate "subsystem == \"$BUNDLE_ID\""
}

cmd_reset() {
  use_xcode
  local name udid
  while IFS= read -r name; do
    udid="$(udid_or_die "$name")"
    release_slot "$udid"
    xcrun simctl erase "$udid"
    say "Erased $name. Run scripts/sim.sh setup to boot it again."
  done < <(targets "${1:-both}")
}

cmd_help() {
  cat <<'EOF'
Glow Simulator workflow (docs/SPEC.md, "Simulator workflow")

  scripts/sim.sh setup [A|B|both]      create and boot Glow A and Glow B (setup A boots just A)
  scripts/sim.sh build                 xcodegen, then xcodebuild Debug for the Simulator
  scripts/sim.sh install [A|B|both]    install the Debug app and launch it
  scripts/sim.sh launch [A|B|both]     relaunch the installed app
  scripts/sim.sh at venue|away         move both to the demo room's center, or 2 km away
  scripts/sim.sh photos                add fixture outfit photos to both photo libraries
  scripts/sim.sh scan <slug>           open a room's link, as if its QR was scanned (scan demo)
  scripts/sim.sh open <url>            open any link on both
  scripts/sim.sh push A <event>        send a fixture notification (push A match_created)
  scripts/sim.sh allow-push [A|B|both] grant notification permission (once per Simulator)
  scripts/sim.sh shot <name>           save a screenshot of both to docs/shots/<name>-A.png and -B.png
  scripts/sim.sh record [name] [secs]  record both screens until Ctrl-C, or for secs seconds
  scripts/sim.sh test [Module]         unit and UI tests on Glow A; or one module (test AppCore),
                                       test unit (no UI tests), test ui, test Glow (app target)
  scripts/sim.sh lint                  SwiftFormat and SwiftLint, as CI runs them
  scripts/sim.sh verify-project        xcodegen twice gives the same project; no .xcodeproj in git
  scripts/sim.sh logs [A|B]            stream the app's logs
  scripts/sim.sh reset [A|B|both]      erase the Simulators
  scripts/sim.sh teardown [A|B|both]   shut down and delete this agent's Simulators
  scripts/sim.sh release [A|B|both]    shut down this agent's Simulators and free their slots
  scripts/sim.sh slots                 who holds the Mac's Simulator slots (3) and build slots (4)

Most commands take A, B or both (the default) as their last argument.

Parallel agents: eval "$(scripts/agent-env.sh <ID>)" first, so GLOW_SIM_A and GLOW_SIM_B name
this agent's own Simulators and GLOW_API_BASE_URL points the app at this agent's server.
At most 3 Glow Simulators are booted on this Mac at once: setup, install and test wait for a free
slot, and test shuts Glow A down and frees its slot when it finishes. At most 4 xcodebuild runs
(build, test, allow-push) go at once; the rest wait for a build slot.
EOF
}

command="${1:-help}"
[ $# -gt 0 ] && shift
case "$command" in
  setup) cmd_setup "$@" ;;
  build) cmd_build "$@" ;;
  install) cmd_install "$@" ;;
  launch) cmd_launch "$@" ;;
  at) cmd_at "$@" ;;
  photos) cmd_photos "$@" ;;
  scan) cmd_scan "$@" ;;
  open) cmd_open "$@" ;;
  push) cmd_push "$@" ;;
  allow-push) cmd_allow_push "$@" ;;
  shot) cmd_shot "$@" ;;
  record) cmd_record "$@" ;;
  test) cmd_test "$@" ;;
  lint) cmd_lint "$@" ;;
  verify-project) cmd_verify_project "$@" ;;
  logs) cmd_logs "$@" ;;
  reset) cmd_reset "$@" ;;
  teardown) cmd_teardown "$@" ;;
  release) cmd_release "$@" ;;
  slots) cmd_slots "$@" ;;
  help | -h | --help) cmd_help ;;
  *) die "unknown command '$command'. Run: scripts/sim.sh help" ;;
esac

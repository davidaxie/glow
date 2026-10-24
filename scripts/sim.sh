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

boot() {
  local udid="$1"
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
    say "Booting $name ($udid)"
    boot "$udid"
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
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"
    say "Deleted $name ($udid)"
  done < <(targets "$which")
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
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" ${extra[@]+"${extra[@]}"} "$@"
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
    boot "$udid"
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
    say "Granting notification permission on $name (log: ios/build/logs/allow-push.log)"
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
  say "SwiftFormat"
  (cd "$ROOT" && swiftformat --lint --quiet .)
  say "SwiftLint"
  (cd "$ROOT" && swiftlint lint --strict --quiet)
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
    xcrun simctl shutdown "$udid" 2>/dev/null || true
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

Most commands take A, B or both (the default) as their last argument.

Parallel agents: eval "$(scripts/agent-env.sh <ID>)" first, so GLOW_SIM_A and GLOW_SIM_B name
this agent's own Simulators and GLOW_API_BASE_URL points the app at this agent's server.
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
  help | -h | --help) cmd_help ;;
  *) die "unknown command '$command'. Run: scripts/sim.sh help" ;;
esac

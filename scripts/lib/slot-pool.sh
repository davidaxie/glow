# Owner: A1. Sourced by sim.sh, agent-env.sh and ci-local.sh. Not run on its own.
#
# The Mac's shared slot pool. Simulators, xcodebuild runs and local database stacks are limited
# across every project on this Mac (Glow, Double Blind, Nudge, ...) by `mac-slots`
# (~/.local/bin/mac-slots; `mac-slots status` shows who holds what). Glow's project name there
# is `glow`. When mac-slots isn't installed, the scripts fall back to Glow's own slot limits and
# say so, once per run.

GLOW_POOL_PROJECT="glow"
GLOW_POOL_DIR="${MAC_SLOTS_DIR:-/tmp/mac-slots}"

# Where mac-slots lives: on PATH, or in ~/.local/bin.
pool_bin() {
  if command -v mac-slots >/dev/null 2>&1; then
    command -v mac-slots
  elif [ -x "$HOME/.local/bin/mac-slots" ]; then
    echo "$HOME/.local/bin/mac-slots"
  else
    return 1
  fi
}

# True when the shared pool is in use. Warns once, on stderr, when it isn't.
pool_on() {
  if [ -z "${GLOW_POOL_BIN:-}" ]; then
    GLOW_POOL_BIN="$(pool_bin || true)"
    if [ -z "$GLOW_POOL_BIN" ]; then
      GLOW_POOL_BIN="none"
      printf 'warning: mac-slots is not installed (expected ~/.local/bin/mac-slots), so Glow uses its own\n' >&2
      printf '         slot limits, which other projects on this Mac do not see.\n' >&2
    fi
  fi
  [ "$GLOW_POOL_BIN" != none ]
}

# mac-slots <args...>, when the pool is on.
pool() {
  "$GLOW_POOL_BIN" "$@"
}

# The process that owns a slot: GLOW_SLOT_OWNER_PID if set (ci-local sets it to itself), else
# the nearest ancestor that isn't a shell, which for an agent is the agent's own long-lived
# process and for a person is their terminal. When it dies (an outage, a crash), the slot is
# freed (and, for a Simulator, the Simulator shut down).
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

# The first field of a mac-slots slot's owner file: the owning process.
pool_slot_pid() { # <slot path>
  cut -d' ' -f1 "$1/owner" 2>/dev/null
}

pool_slot_alive() { # <slot path>: the slot still exists and its owner process is running
  local pid
  [ -d "$1" ] || return 1
  pid="$(pool_slot_pid "$1")"
  [ -n "$pid" ] && [ "$pid" != 0 ] && kill -0 "$pid" 2>/dev/null
}

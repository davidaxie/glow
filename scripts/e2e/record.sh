#!/usr/bin/env bash
# Owner: D1. The two-Simulator recording: runs a journey with both apps side by side, Glow A
# driven by the UI test and Glow B signed in as the person player B plays, records both screens,
# and joins them into one side-by-side video.
#
#   eval "$(scripts/agent-env.sh <ID>)"
#   scripts/e2e/record.sh            # the full loop
#   scripts/e2e/record.sh chat       # any journey run.sh knows
#
# Writes docs/shots/d1-e2e-<journey>-A.mp4, -B.mp4 and, with ffmpeg, d1-e2e-<journey>.mp4.
# Takes both of this agent's Simulator slots for the run, and gives them back at the end.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JOURNEY="${1:-full}"
shift || true
"$ROOT/scripts/e2e/run.sh" "$JOURNEY" --record "$@"

A="$ROOT/docs/shots/d1-e2e-$JOURNEY-A.mp4"
B="$ROOT/docs/shots/d1-e2e-$JOURNEY-B.mp4"
OUT="$ROOT/docs/shots/d1-e2e-$JOURNEY.mp4"
if command -v ffmpeg >/dev/null && [ -f "$A" ] && [ -f "$B" ]; then
  # Same height, side by side, A on the left. Small enough to commit.
  ffmpeg -loglevel error -y -i "$A" -i "$B" \
    -filter_complex "[0:v]scale=-2:960[a];[1:v]scale=-2:960[b];[a][b]hstack=inputs=2[v]" \
    -map "[v]" -c:v libx264 -crf 30 -preset veryfast -pix_fmt yuv420p "$OUT"
  printf '==> Saved %s\n' "${OUT#"$ROOT/"}"
else
  printf '==> Saved %s and %s (install ffmpeg to join them)\n' "${A#"$ROOT/"}" "${B#"$ROOT/"}"
fi

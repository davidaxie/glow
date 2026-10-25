#!/usr/bin/env python3
"""Records the demo video's phone clips from the real app on headless Simulators (V1).

Every clip is the Debug build of Glow running in the iOS Simulator, driven by its Debug launch
arguments and fixtures (no server, no real people). Nothing here opens a window: recording uses
`xcrun simctl io <device> recordVideo`.

    export GLOW_SIM_A='Glow A (V1)' GLOW_SIM_B='Glow B (V1)' MAC_SLOTS_SIM=5
    scripts/sim.sh setup both && scripts/sim.sh build && scripts/sim.sh install both
    python3 scripts/video/capture.py <out dir> [clip ...]

The Blind clips that need taps and typing (deck swipes, the give-away warning, Waiting and the
mutual reveal) come from `ios/GlowUITests/DemoVideoUITests.swift`, recorded by `ui-capture.py`.
"""

import json
import os
import signal
import subprocess
import sys
import time

BUNDLE = "com.davidxie.glow"
ROOM = "de000000-0000-4000-8000-000000000001"
SIM_A = os.environ.get("GLOW_SIM_A", "Glow A (V1)")
SIM_B = os.environ.get("GLOW_SIM_B", "Glow B (V1)")
os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

# name: (seconds, {device letter: launch arguments})
CLIPS = {
    # Rooms: the fixture room's home, then the deck opening a look and tapping it (one-sided).
    "room-home": (9, {"A": ["-GlowDebugDeckFixture", "normal", "-GlowDebugRoute", f"room/{ROOM}"]}),
    "deck-tap": (
        16,
        {"A": ["-GlowDebugDeckFixture", "normal", "-GlowDebugDeckAutoplay", "tap", "-GlowDebugRoute", f"deck/{ROOM}"]},
    ),
    # The mutual moment on both phones at once: match.created after 2 s, both choose Find, both glow.
    "mutual": (
        26,
        {
            letter: [
                "-GlowPreviewSession", "ready", "-GlowMatchFixtures", "reveal", "-GlowMatchFixturesChoose", "find",
                "-GlowGlowFixtures", "aqua",
            ]
            for letter in ("A", "B")
        },
    ),
    # Blind: the drop opening by itself, codename cards turning over.
    "blind-drop": (
        14,
        {
            "A": [
                "-GlowPreviewSession", "ready", "-GlowDebugBlind", "dropReady", "-GlowDebugBlindAutoOpen", "YES",
                "-GlowDebugRoute", "blindDrop",
            ]
        },
    ),
    "blind-deck": (8, {"A": ["-GlowPreviewSession", "ready", "-GlowDebugBlind", "swiping", "-GlowDebugRoute", "blind"]}),
    "blind-revealed": (
        10,
        {
            "A": [
                "-GlowPreviewSession", "ready", "-GlowDebugBlind", "revealed",
                "-GlowDebugRoute", "blindReveal/b1c40000-0000-4000-8000-000000000001",
            ]
        },
    ),
}


def udid(name: str) -> str:
    out = subprocess.run(["xcrun", "simctl", "list", "-j", "devices", "available"], capture_output=True, text=True, check=True)
    for devices in json.loads(out.stdout)["devices"].values():
        for device in devices:
            if device["name"] == name:
                return device["udid"]
    sys.exit(f"capture.py: no Simulator named {name}. Run scripts/sim.sh setup both")


def record(out_dir: str, clip: str) -> None:
    seconds, launches = CLIPS[clip]
    devices = {"A": udid(SIM_A), "B": udid(SIM_B)}
    recorders = []
    for letter in launches:
        subprocess.run(["xcrun", "simctl", "terminate", devices[letter], BUNDLE], capture_output=True)
    time.sleep(0.8)
    for letter in launches:
        path = os.path.join(out_dir, f"{clip}-{letter}.mp4")
        recorders.append(
            subprocess.Popen(
                ["xcrun", "simctl", "io", devices[letter], "recordVideo", "--codec=h264", "--force", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        )
    time.sleep(1.5)
    launchers = [
        subprocess.Popen(["xcrun", "simctl", "launch", devices[letter], BUNDLE, *args], stdout=subprocess.DEVNULL)
        for letter, args in launches.items()
    ]
    for launcher in launchers:
        launcher.wait()
    time.sleep(seconds)
    for recorder in recorders:
        recorder.send_signal(signal.SIGINT)
    for recorder in recorders:
        recorder.wait(timeout=30)
    print(f"recorded {clip} ({', '.join(launches)})")


def main() -> None:
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    for clip in sys.argv[2:] or list(CLIPS):
        record(out_dir, clip)


if __name__ == "__main__":
    main()

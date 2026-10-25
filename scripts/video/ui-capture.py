#!/usr/bin/env python3
"""Records Blind mode's tapped moments for the demo video (V1) from the real app.

Starts `simctl io recordVideo` on Glow A, runs `ios/GlowUITests/DemoVideoUITests.swift` through
`scripts/sim.sh test` (headless), stops the recorder as soon as the suite finishes (before sim.sh
shuts the Simulator down), and writes when each test started, relative to the recording, so the
editor can cut each moment out:

    python3 scripts/video/ui-capture.py <out dir>     ->  <out dir>/blind-ui-A.mp4, blind-ui.json
"""

import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOG = os.path.join(ROOT, "ios", "build", "logs", "test.log")
SIM_A = os.environ.get("GLOW_SIM_A", "Glow A (V1)")
os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")


def udid(name: str) -> str:
    out = subprocess.run(["xcrun", "simctl", "list", "-j", "devices", "available"], capture_output=True, text=True, check=True)
    for devices in json.loads(out.stdout)["devices"].values():
        for device in devices:
            if device["name"] == name:
                return device["udid"]
    sys.exit(f"ui-capture.py: no Simulator named {name}")


def main() -> None:
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    video = os.path.join(out_dir, "blind-ui-A.mp4")
    if os.path.exists(LOG):
        os.remove(LOG)
    device = udid(SIM_A)
    subprocess.run(["xcrun", "simctl", "boot", device], capture_output=True)
    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", "--force", video],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    # recordVideo prints "Recording started" once the first frame is written.
    started = None
    while started is None:
        line = recorder.stderr.readline()
        if not line:
            break
        if "Recording started" in line:
            started = time.time()
    started = started or time.time()
    env = dict(os.environ, TEST_RUNNER_GLOW_DEMO_VIDEO="1")  # the tests skip themselves without it
    test = subprocess.Popen([os.path.join(ROOT, "scripts", "sim.sh"), "test", "GlowUITests/DemoVideoUITests"], cwd=ROOT, env=env)
    done = re.compile(r"Test Suite 'DemoVideoUITests' (passed|failed)")
    while test.poll() is None:
        if os.path.exists(LOG):
            with open(LOG, errors="replace") as handle:
                if done.search(handle.read()):
                    break
        time.sleep(0.3)
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=60)
    test.wait()

    marks = []
    with open(LOG, errors="replace") as handle:
        for line in handle:
            match = re.search(r"Test Case '-\[GlowUITests\.DemoVideoUITests (\w+)\]' started", line)
            if match:
                marks.append({"test": match.group(1)})
            match = re.search(r"Start Test at (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)", line)
            if match and marks and "start" not in marks[-1]:
                when = dt.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp()
                marks[-1]["start"] = round(when - started, 2)
            match = re.search(r"t = +([\d.]+)s DEMO (.+)$", line)
            if match and marks and "start" in marks[-1]:
                marks[-1].setdefault("events", []).append([round(marks[-1]["start"] + float(match.group(1)), 2), match.group(2).strip()])
            match = re.search(r"Test Case '-\[GlowUITests\.DemoVideoUITests (\w+)\]' (passed|failed)", line)
            if match and marks:
                marks[-1]["result"] = match.group(2)
    with open(os.path.join(out_dir, "blind-ui.json"), "w") as handle:
        json.dump(marks, handle, indent=2)
    print(json.dumps(marks, indent=2))


if __name__ == "__main__":
    main()

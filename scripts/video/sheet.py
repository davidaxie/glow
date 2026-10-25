#!/usr/bin/env python3
"""Contact sheets for reviewing clips like a film editor: one frame every STEP seconds, 10 per row.

    python3 scripts/video/sheet.py <out dir> <step seconds> <width> clip.mp4 [clip.mp4 ...]
    python3 scripts/video/sheet.py --frames <out dir> <every seconds> final.mp4   (full-size stills)
"""

import math
import os
import subprocess
import sys


def duration(path: str) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True,
    )
    return float(out.stdout.strip())


def sheet(out_dir: str, step: float, width: int, clip: str) -> None:
    dur = duration(clip)
    count = max(1, math.ceil(dur / step))
    rows = math.ceil(count / 10)
    out = os.path.join(out_dir, os.path.splitext(os.path.basename(clip))[0] + ".png")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", clip, "-vf", f"fps=1/{step},scale={width}:-1,tile=10x{rows}", "-frames:v", "1", out],
        check=True,
    )
    print(f"{out}: {dur:.2f}s, {count} frames")


def frames(out_dir: str, every: float, clip: str) -> None:
    dur = duration(clip)
    t = every / 2
    while t < dur:
        out = os.path.join(out_dir, f"f{t:06.2f}.jpg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.2f}", "-i", clip, "-frames:v", "1", "-q:v", "3", out], check=True)
        t += every
    print(f"stills every {every}s of {dur:.2f}s in {out_dir}")


def main() -> None:
    if sys.argv[1] == "--frames":
        os.makedirs(sys.argv[2], exist_ok=True)
        frames(sys.argv[2], float(sys.argv[3]), sys.argv[4])
        return
    out_dir, step, width = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
    os.makedirs(out_dir, exist_ok=True)
    for clip in sys.argv[4:]:
        sheet(out_dir, step, width, clip)


if __name__ == "__main__":
    main()

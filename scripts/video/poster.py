#!/usr/bin/env python3
"""Poster (1920x1080) and Devpost thumbnail (3:2, 1500x1000) from the rendered demo video (V1).

    python3 scripts/video/poster.py <glow-demo.mp4> <out dir> [poster second]

The poster is a frame of the cut (both phones glowing the same color). The thumbnail reuses those
two phones from the same frame, with the wordmark set in New York.
"""

import os
import subprocess
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import AQUA, GREY, PINK, TEXT, canvas, sans, serif, typeset  # noqa: E402


def main() -> None:
    video, out_dir = sys.argv[1], sys.argv[2]
    at = sys.argv[3] if len(sys.argv) > 3 else "45"
    poster = os.path.join(out_dir, "glow-demo-poster.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", at, "-i", video, "-frames:v", "1", poster], check=True)
    frame = Image.open(poster).convert("RGB")
    phones = frame.crop((905, 80, 1855, 1000))  # both phones, bezels and spill
    thumb = canvas([((1500 * 0.62, 1000 * 0.5), 820, AQUA, 0.16), ((200, 120), 700, PINK, 0.05)]).crop((0, 0, 1500, 1000))
    thumb = thumb.convert("RGBA")
    scale = 860 / phones.height
    phones = phones.resize((round(phones.width * scale), 860), Image.LANCZOS)
    thumb.paste(phones, (1500 - phones.width - 24, 70))
    d = ImageDraw.Draw(thumb)
    d.text((72, 270), "Glow", font=serif(150, "Semibold"), fill=TEXT + (255,))
    d.text((78, 480), "Same color.", font=serif(56), fill=TEXT + (255,))
    d.text((78, 550), "Same word.", font=serif(56), fill=TEXT + (255,))
    d.text((80, 650), typeset("Find out, privately,"), font=sans(28), fill=GREY + (255,))
    d.text((80, 690), "that you noticed", font=sans(28), fill=GREY + (255,))
    d.text((80, 730), "each other.", font=sans(28), fill=GREY + (255,))
    thumb.convert("RGB").save(os.path.join(out_dir, "glow-thumb-3x2.png"))
    print(f"wrote {poster} and glow-thumb-3x2.png")


if __name__ == "__main__":
    main()

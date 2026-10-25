#!/usr/bin/env python3
"""Renders Glow's demo video (V1): 1920x1080, 30 fps, H.264 with AAC.

Every phone screen in the cut is a Simulator recording of the real Debug app (`capture.py` and
`ui-capture.py`); this script only frames them. Title cards and captions are transparent PNGs
drawn with Pillow (this ffmpeg has no drawtext) and laid over with ffmpeg; the soundtrack is
synthesized here with numpy (a warm pad plus a few soft chimes on the key moments). No downloaded
assets, no music.

    python3 scripts/video/render.py <raw clips dir> <work dir> <out.mp4>

The timeline below is the edit: each segment is a title card or one or two phones with captions.
"""

import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
XFADE = 0.6
FONTS = "/System/Library/Fonts"
SERIF = f"{FONTS}/NewYork.ttf"
SERIF_ITALIC = f"{FONTS}/NewYorkItalic.ttf"
SANS = f"{FONTS}/SFNS.ttf"

CANVAS = (11, 10, 15)
TEXT = (245, 243, 240)
GREY = (169, 163, 157)
DIM = (120, 115, 110)
PINK = (253, 77, 160)
AQUA = (64, 224, 204)
VIOLET = (138, 124, 255)
WARM = (255, 170, 120)

# Phone screens: the Simulator records 1206x2622 (iPhone 17 Pro).
SRC_W, SRC_H = 1206, 2622
ONE = dict(h=900)  # one phone
TWO = dict(h=860)  # two phones side by side

# --- The edit -----------------------------------------------------------------------------------
# kind "title": full-screen type. kind "phones": one or two clips, each (file, start second in the
# raw recording), with captions [(from, to, eyebrow, title, sub)] in segment time. light: the color
# of the light behind the phones. cues: sounds [(segment time, sound)].
TIMELINE = [
    dict(
        name="open", kind="title", dur=7.0, light=WARM,
        lines=[(0.4, "You notice someone across the room.", 76), (2.9, "You never find out if they noticed you too.", 44)],
        cues=[(0.3, "pad-in")],
    ),
    dict(
        name="glow", kind="title", dur=5.2, light=PINK, wordmark=True,
        lines=[(0.5, "Glow", 150), (1.4, "Notice someone. Find out if it's mutual.", 40)],
        cues=[(0.5, "chime-low")],
    ),
    dict(
        name="rooms", kind="chapter", dur=3.4, light=PINK,
        eyebrow="Mode one", title="Rooms", sub="For a room you're both in: a class, a party, this hackathon.",
    ),
    dict(
        name="room", kind="phones", dur=5.4, light=PINK, clips=[("room-home-A.mp4", 2.2)],
        captions=[(0.0, 5.4, "Rooms", "Check in to the room.", "Scan its QR code. Glow checks once that you're inside, then forgets where you are.")],
    ),
    dict(
        name="deck", kind="phones", dur=11.0, light=PINK, clips=[("deck-tap-A.mp4", 2.4)],
        captions=[
            (0.0, 3.5, "Today's looks", "Outfits, not profiles.", "Faces are blurred on the phone. No names, no distance."),
            (3.5, 7.4, "One tap", "Tap the one you noticed.", "They aren't told. Not now, not ever, unless they tap you too."),
            (7.4, 11.0, "One-sided", "Noted. Only you know.", "If it isn't mutual, nothing happens. Ever."),
        ],
        cues=[(7.7, "chime-soft")],
    ),
    dict(
        # Plays 3.5 s, then holds the "noticed you back" frame (the takeover moves on to the profile).
        name="mutual", kind="phones", dur=5.6, light=PINK, clips=[("mutual-A.mp4", 3.4, 3.5), ("mutual-B.mp4", 3.4, 3.5)],
        captions=[(0.0, 5.6, "It's mutual", "Both phones, the same moment.", "Someone you noticed noticed you back.")],
        cues=[(0.6, "heartbeat"), (0.9, "chime-mutual")],
    ),
    dict(
        name="find", kind="phones", dur=6.6, light=PINK, clips=[("mutual-A.mp4", 7.5)],
        captions=[(0.0, 6.6, "Find each other?", "Only if you both say yes.", "Each of you chooses Find each other or Just chat.")],
    ),
    dict(
        name="glow-both", kind="phones", dur=10.0, light=AQUA, clips=[("mutual-A.mp4", 15.5), ("mutual-B.mp4", 15.5)],
        captions=[
            (0.0, 10.0, "The glow", "Same color. Same word.", "Both screens light up so you can find each other across a loud room. Say the word."),
        ],
        cues=[(0.0, "heartbeat"), (0.2, "swell"), (0.9, "chime-glow")],
    ),
    dict(
        name="blind", kind="chapter", dur=3.4, light=VIOLET,
        eyebrow="Mode two", title="Blind", sub="Chat first. Find out who later.",
        cues=[(0.4, "chime-low")],
    ),
    dict(
        name="swipe", kind="phones", dur=9.6, light=VIOLET, clips=[("blind-ui-A.mp4", 39.6)],
        captions=[(0.0, 9.6, "Blind", "Swipe on photos only.", "Mutual likes stay hidden until the nightly drop.")],
    ),
    dict(
        name="drop", kind="phones", dur=7.6, light=VIOLET, clips=[("blind-drop-A.mp4", 2.0)],
        captions=[(0.0, 7.6, "The drop", "Your matches open at once.", "As chats, behind codenames. You liked them, but which one is Fox?")],
        cues=[(2.9, "sparkle")],
    ),
    dict(
        name="warn", kind="phones", dur=10.6, light=VIOLET, clips=[("blind-ui-A.mp4", 63.4)],
        captions=[(0.0, 10.6, "Blind chat", "Talk without giving yourself away.", "Before a handle, a name or a number goes out, Glow warns you first.")],
    ),
    dict(
        name="wait", kind="phones", dur=8.0, light=VIOLET, clips=[("blind-ui-A.mp4", 77.2)],
        captions=[(0.0, 8.0, "Reveal", "Reveal is mutual too.", "Tap Reveal and nothing changes for them. You wait.")],
    ),
    dict(
        name="veil", kind="phones", dur=11.6, light=VIOLET, clips=[("blind-ui-A.mp4", 94.8)],
        captions=[(0.0, 11.6, "Both said yes", "The veil lifts.", "Names and photos, for the first time, for both of you.")],
        cues=[(5.3, "heartbeat"), (5.5, "swell"), (6.1, "chime-glow")],
    ),
    dict(
        name="end", kind="end", dur=8.0, light=PINK,
        cues=[(0.6, "chime-low"), (7.0, "pad-out")],
    ),
]


# --- Drawing helpers -------------------------------------------------------------------------------


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def sans(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    f = font(SANS, size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def serif(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    """New York with an optical size that suits the pixel size (its default is the 256 pt cut)."""
    f = font(SERIF, size)
    try:
        f.set_variation_by_axes([max(12, min(256, size * 0.75)), 590 if weight == "Semibold" else 400, 0])
    except (OSError, ValueError):
        pass
    return f


def typeset(text: str) -> str:
    return text.replace("'", "’")


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def tracked(draw: ImageDraw.ImageDraw, xy, text: str, f, fill, tracking: float) -> float:
    """Draws letter-spaced text (eyebrows); returns the width."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking
    return x - xy[0]


def tracked_width(draw, text, f, tracking) -> float:
    return sum(draw.textlength(ch, font=f) + tracking for ch in text) - tracking


def radial(size, center, radius, color, alpha) -> Image.Image:
    """A soft radial light (RGBA) of `color`, peaking at `alpha` (0..1)."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2.2 * alpha
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = color
    out[..., 3] = a * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def canvas(lights: list[tuple]) -> Image.Image:
    """The warm dark room: a vertical gradient, soft lights, a vignette and faint grain."""
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    top, bottom = np.array([20, 17, 24], np.float32), np.array(CANVAS, np.float32)
    base = top + (bottom - top) * yy
    img = np.repeat(base[None, :, :], W, axis=0).transpose(1, 0, 2).copy()
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(np.float32)
    for (cx, cy), radius, color, alpha in lights:
        d = np.sqrt((xx2 - cx) ** 2 + (yy2 - cy) ** 2) / radius
        a = (np.clip(1 - d, 0, 1) ** 2.0 * alpha)[..., None]
        img = img + (np.array(color, np.float32) - img) * a
    d = np.sqrt(((xx2 - W / 2) / (W * 0.75)) ** 2 + ((yy2 - H / 2) / (H * 0.85)) ** 2)
    img *= (1 - np.clip(d - 0.35, 0, 1) * 0.55)[..., None]
    rng = np.random.default_rng(7)
    img += rng.normal(0, 2.2, (H, W, 1)).astype(np.float32)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def rounded_mask(size, radius, scale=4) -> Image.Image:
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def phone_geometry(count: int):
    """Screen rectangles (x, y, w, h) for one or two phones, on the right of the frame."""
    h = (ONE if count == 1 else TWO)["h"]
    w = round(h * SRC_W / SRC_H / 2) * 2
    y = (H - h) // 2
    if count == 1:
        cx = [1330]
    else:
        cx = [1135, 1625]
    return [(c - w // 2, y, w, h) for c in cx]


BEZEL = 14


def draw_phone_body(img: Image.Image, rect, light) -> None:
    """The titanium frame, shadow and a soft spill of screen light, under the screen."""
    x, y, w, h = rect
    r = round(w * 0.142)
    ox, oy, ow, oh = x - BEZEL, y - BEZEL, w + 2 * BEZEL, h + 2 * BEZEL
    # Light from the screen and a shadow under the phone.
    spill = radial((W, H), (x + w / 2, y + h / 2), h * 0.78, light, 0.34 if light == AQUA else 0.22)
    img.alpha_composite(spill)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((ox + 10, oy + 26, ox + ow + 10, oy + oh + 26), r + BEZEL, fill=(0, 0, 0, 170))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    s = 4
    body = Image.new("RGBA", ((ow + 8) * s, (oh + 8) * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    o = 4 * s
    # Side buttons.
    for by, bh in [(0.17, 0.035), (0.235, 0.075), (0.325, 0.075)]:
        d.rounded_rectangle((o - 3 * s, o + oh * by * s, o + 2 * s, o + (oh * by + oh * bh) * s), 2 * s, fill=(58, 55, 62, 255))
    d.rounded_rectangle((o + ow * s - 2 * s, o + oh * 0.27 * s, o + ow * s + 3 * s, o + oh * 0.37 * s), 2 * s, fill=(58, 55, 62, 255))
    # Outer rim (catching light), titanium band, inner black border.
    d.rounded_rectangle((o, o, o + ow * s, o + oh * s), (r + BEZEL) * s, fill=(92, 88, 98, 255))
    d.rounded_rectangle((o + 2 * s, o + 2 * s, o + (ow - 2) * s, o + (oh - 2) * s), (r + BEZEL - 2) * s, fill=(44, 41, 48, 255))
    d.rounded_rectangle((o + 5 * s, o + 5 * s, o + (ow - 5) * s, o + (oh - 5) * s), (r + BEZEL - 5) * s, fill=(6, 6, 8, 255))
    body = body.resize((ow + 8, oh + 8), Image.LANCZOS)
    img.alpha_composite(body, (ox - 4, oy - 4))


def caption_png(path: str, eyebrow: str, title: str, sub: str, accent) -> None:
    eyebrow, title, sub = typeset(eyebrow), typeset(title), typeset(sub)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x, width = 150, 720
    fe, ft, fs = sans(24, "Semibold"), serif(68), sans(31)
    title_lines = wrap(d, title, ft, width)
    sub_lines = wrap(d, sub, fs, 640)
    total = 34 + len(title_lines) * 80 + 26 + len(sub_lines) * 44
    y = (H - total) // 2 - 10
    tracked(d, (x, y), eyebrow.upper(), fe, accent + (255,), 4.2)
    y += 34 + 14
    for line in title_lines:
        d.text((x - 2, y), line, font=ft, fill=TEXT + (255,))
        y += 80
    y += 22
    for line in sub_lines:
        d.text((x, y), line, font=fs, fill=GREY + (255,))
        y += 44
    img.save(path)


def footer(img: Image.Image) -> None:
    d = ImageDraw.Draw(img)
    f = sans(20)
    text = "Recorded in the iOS Simulator"
    d.text((150, H - 70), text, font=f, fill=DIM + (255,))


def title_png(path: str, seg) -> list[str]:
    """Title cards: one PNG per line, so each can fade in on its own."""
    paths = []
    lines = seg["lines"]
    heights = [size * 1.25 for _, _, size in lines]
    gap = 34
    y = (H - (sum(heights) + gap * (len(lines) - 1))) / 2
    for i, (_, text, size) in enumerate(lines):
        text = typeset(text)
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        if seg.get("wordmark") and i == 0:
            f, fill = serif(size, "Semibold"), TEXT
        elif i == 0:
            f, fill = serif(size), TEXT
        else:
            f, fill = (serif(size) if not seg.get("wordmark") else sans(size)), GREY
        tw = d.textlength(text, font=f)
        d.text(((W - tw) / 2, y), text, font=f, fill=fill + (255,))
        y += heights[i] + gap
        p = f"{path}-{i}.png"
        img.save(p)
        paths.append(p)
    return paths


def chapter_png(path: str, seg) -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fe, ft, fs = sans(26, "Semibold"), serif(132), sans(36)
    accent = seg["light"]
    ew = tracked_width(d, seg["eyebrow"].upper(), fe, 5)
    tracked(d, ((W - ew) / 2, 370), seg["eyebrow"].upper(), fe, accent + (255,), 5)
    tw = d.textlength(seg["title"], font=ft)
    d.text(((W - tw) / 2, 420), seg["title"], font=ft, fill=TEXT + (255,))
    sub = typeset(seg["sub"])
    sw = d.textlength(sub, font=fs)
    d.text(((W - sw) / 2, 610), sub, font=fs, fill=GREY + (255,))
    img.save(path)


def end_pngs(work: str) -> list[str]:
    a = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    fw, ft = serif(170, "Semibold"), serif(46)
    tw = d.textlength("Glow", font=fw)
    d.text(((W - tw) / 2, 300), "Glow", font=fw, fill=TEXT + (255,))
    line = typeset("Notice someone. Find out if it's mutual.")
    lw = d.textlength(line, font=ft)
    d.text(((W - lw) / 2, 530), line, font=ft, fill=GREY + (255,))
    b = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(b)
    fc, fs = sans(30, "Medium"), sans(24)
    credit = "Built at Cal Hacks 13.0 by David Xie and Robin Dao"
    cw = d.textlength(credit, font=fc)
    d.text(((W - cw) / 2, 760), credit, font=fc, fill=TEXT + (230,))
    modes = "Rooms  ·  Blind  ·  SwiftUI, Next.js, Supabase, Claude"
    mw = d.textlength(modes, font=fs)
    d.text(((W - mw) / 2, 812), modes, font=fs, fill=GREY + (255,))
    rec = "Every screen recorded from the real app in the iOS Simulator"
    rw = d.textlength(rec, font=fs)
    d.text(((W - rw) / 2, H - 92), rec, font=fs, fill=DIM + (255,))
    pa, pb = os.path.join(work, "end-a.png"), os.path.join(work, "end-b.png")
    a.save(pa)
    b.save(pb)
    return [pa, pb]


# --- Segments --------------------------------------------------------------------------------------


def run(cmd: list[str]) -> None:
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stderr[-3000:])
        sys.exit(f"ffmpeg failed: {' '.join(cmd[:8])} ...")


def fading(index: int, start: float, end: float, dur: float, fade: float = 0.45) -> str:
    """Alpha fades for an overlay that shows from start to end within a segment of dur seconds."""
    parts = ["format=rgba"]
    if start > 0.01:
        parts.append(f"fade=t=in:st={start:.2f}:d={fade}:alpha=1")
    if end < dur - 0.01:
        parts.append(f"fade=t=out:st={end - fade:.2f}:d={fade}:alpha=1")
    return ",".join(parts)


def resolve_clip(raw: str, name: str, start: float, ui_marks: dict) -> tuple[str, float]:
    if name.startswith("ui:"):
        test = name[3:]
        return os.path.join(raw, "blind-ui-A.mp4"), ui_marks[test] + start
    return os.path.join(raw, name), start


def render_segment(seg, i: int, raw: str, work: str, ui_marks: dict) -> str:
    out = os.path.join(work, f"seg{i:02d}-{seg['name']}.mp4")
    dur = seg["dur"]
    light = seg["light"]
    inputs, filters, overlays = [], [], []
    if seg["kind"] == "phones":
        rects = phone_geometry(len(seg["clips"]))
        bg = canvas([((W * 0.2, H * 0.1), 900, WARM, 0.035)]).convert("RGBA")
        for rect in rects:
            draw_phone_body(bg, rect, light)
        footer(bg)
        bg_path = os.path.join(work, f"bg{i:02d}.png")
        bg.convert("RGB").save(bg_path)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur}", "-i", bg_path]
        x, y, w, h = rects[0]
        mask_path = os.path.join(work, f"mask-{w}x{h}.png")
        rounded_mask((w, h), round(w * 0.142)).save(mask_path)
        current = "[0:v]"
        n = 1
        for k, spec in enumerate(seg["clips"]):
            # (file, start) plays for the whole segment; (file, start, length) then holds its last frame.
            clip, start = spec[0], spec[1]
            length = spec[2] if len(spec) > 2 else dur + 0.5
            path, at = resolve_clip(raw, clip, start, ui_marks)
            inputs += ["-ss", f"{at:.2f}", "-t", f"{length}", "-i", path]
            inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur}", "-i", mask_path]
            filters.append(f"[{n}:v]fps={FPS},scale={w}:{h}:flags=lanczos,format=rgba,setpts=PTS-STARTPTS[s{k}]")
            filters.append(f"[{n + 1}:v]format=gray[m{k}]")
            filters.append(f"[s{k}][m{k}]alphamerge[p{k}]")
            rx, ry, _, _ = rects[k]
            filters.append(f"{current}[p{k}]overlay={rx}:{ry}:shortest=0:eof_action=repeat[b{k}]")
            current = f"[b{k}]"
            n += 2
        for c, (start, end, eyebrow, title, sub) in enumerate(seg.get("captions", [])):
            p = os.path.join(work, f"cap{i:02d}-{c}.png")
            caption_png(p, eyebrow, title, sub, light if light != WARM else PINK)
            overlays.append((p, start, end))
    else:
        lights = [((W / 2, H * 0.42), 760, light, 0.20), ((W * 0.2, H * 0.1), 900, WARM, 0.03)]
        if seg["kind"] == "end":
            lights = [((W / 2, H * 0.40), 820, light, 0.26), ((W * 0.5, H * 0.95), 900, AQUA, 0.05)]
        bg_path = os.path.join(work, f"bg{i:02d}.png")
        canvas(lights).save(bg_path)
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur}", "-i", bg_path]
        current = "[0:v]"
        n = 1
        if seg["kind"] == "title":
            for (start, _, _), p in zip(seg["lines"], title_png(os.path.join(work, f"title{i:02d}"), seg)):
                overlays.append((p, start, dur))
        elif seg["kind"] == "chapter":
            p = os.path.join(work, f"chapter{i:02d}.png")
            chapter_png(p, seg)
            overlays.append((p, 0.25, dur))
        else:
            a, b = end_pngs(work)
            overlays += [(a, 0.4, dur), (b, 1.6, dur)]
    for k, (p, start, end) in enumerate(overlays):
        inputs += ["-loop", "1", "-framerate", str(FPS), "-t", f"{dur}", "-i", p]
        filters.append(f"[{n}:v]{fading(k, start, end, dur)}[o{k}]")
        filters.append(f"{current}[o{k}]overlay=0:0[c{k}]")
        current = f"[c{k}]"
        n += 1
    filters.append(f"{current}format=yuv420p,trim=duration={dur},setpts=PTS-STARTPTS[out]")
    run(
        ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filters), "-map", "[out]",
         "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "14", "-pix_fmt", "yuv420p", "-an", out]
    )
    return out


# --- Soundtrack ------------------------------------------------------------------------------------

SR = 48000


def env_adsr(n, attack, release):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / release)


def bell(freq, dur=4.0, amp=0.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, gain, decay in [(1.0, 1.0, 1.6), (2.0, 0.35, 0.9), (2.76, 0.18, 0.5), (5.4, 0.06, 0.25)]:
        out += gain * np.sin(2 * np.pi * freq * ratio * t) * env_adsr(n, 0.006, decay)
    return amp * out / 1.6


def thump(dur=0.5, amp=0.35):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 62 + 30 * np.exp(-t / 0.03)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * env_adsr(n, 0.004, 0.09)


def swell(dur=4.0, amp=0.16, rng=None):
    n = int(dur * SR)
    noise = rng.normal(0, 1, n)
    spec = np.fft.rfft(noise)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spec *= np.exp(-((np.log(freqs + 1) - np.log(700)) ** 2) / 1.1)
    airy = np.fft.irfft(spec, n)
    airy /= np.abs(airy).max() + 1e-9
    t = np.arange(n) / SR
    shape = np.where(t < 1.5, (t / 1.5) ** 2, np.exp(-(t - 1.5) / 0.9))
    return amp * airy * shape


def pad_voice(freqs, n, rng, level):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, f in enumerate(freqs):
        gain = level / (1 + k * 0.35)
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (0.05 + 0.017 * k) * t + rng.uniform(0, 6.28))
        for det in (-0.0016, 0.0, 0.0019):
            out += gain * lfo * np.sin(2 * np.pi * f * (1 + det) * t + rng.uniform(0, 6.28)) / 3
    return out


def soundtrack(cues: list[tuple[float, str]], total: float, blind_from: float, blind_to: float, path: str) -> None:
    rng = np.random.default_rng(11)
    n = int(total * SR)
    t = np.arange(n) / SR
    d_major = [73.42, 110.0, 146.83, 185.0, 220.0, 277.18, 329.63]  # D, A, D, F#, A, C#, E: Dmaj9
    b_minor = [61.74, 92.5, 146.83, 185.0, 220.0, 277.18, 293.66]  # B, F#, D, F#, A, C#, D: Bm9
    pa, pb = pad_voice(d_major, n, rng, 0.05), pad_voice(b_minor, n, rng, 0.05)
    x = np.clip((t - blind_from) / 3.0, 0, 1) * np.clip((blind_to - t) / 3.0, 0, 1)
    pad = pa * (1 - x) + pb * x
    pad *= np.clip(t / 3.5, 0, 1) * np.clip((total - t) / 4.0, 0, 1)
    left, right = pad.copy(), pad.copy()
    fx = np.zeros(n)

    def add(sig, at, pan=0.0):
        i = int(at * SR)
        j = min(n, i + len(sig))
        if i >= n:
            return
        fx[i:j] += sig[: j - i]

    for at, kind in cues:
        if kind == "chime-low":
            add(bell(587.33, 5, 0.12), at)
            add(bell(880.0, 5, 0.07), at + 0.09)
        elif kind == "chime-soft":
            add(bell(1174.66, 3.5, 0.08), at)
        elif kind == "chime-mutual":
            add(bell(880.0, 4.5, 0.12), at)
            add(bell(1108.73, 4.5, 0.10), at + 0.16)
        elif kind == "chime-glow":
            for k, f in enumerate([587.33, 739.99, 880.0, 1174.66]):
                add(bell(f, 5.5, 0.085), at + k * 0.11)
        elif kind == "heartbeat":
            add(thump(), at)
            add(thump(amp=0.28), at + 0.12 + 0.09)
        elif kind == "swell":
            add(swell(4.5, 0.10, rng), at)
        elif kind == "sparkle":
            for k, f in enumerate([1174.66, 1479.98, 1760.0]):
                add(bell(f, 2.5, 0.05), at + k * 0.28)
    # A simple room: convolve the effects with a decaying noise tail, slightly different per side.
    ir_n = int(2.2 * SR)
    ir_t = np.arange(ir_n) / SR
    size = 1 << int(math.ceil(math.log2(n + ir_n)))
    spec = np.fft.rfft(fx, size)
    for side, chan in ((0, left), (1, right)):
        ir = rng.normal(0, 1, ir_n) * np.exp(-ir_t / 0.55) * 0.02
        ir[0] = 1.0
        wet = np.fft.irfft(spec * np.fft.rfft(ir, size), size)[:n]
        chan += 0.75 * fx + 0.35 * (wet - fx)
    stereo = np.stack([left, right], axis=1)
    stereo /= np.abs(stereo).max() / 10 ** (-6 / 20)
    pcm = (stereo * 32767).astype(np.int16)
    import wave

    with wave.open(path, "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(pcm.tobytes())


# --- Main ------------------------------------------------------------------------------------------


def main() -> None:
    raw, work, out = sys.argv[1], sys.argv[2], sys.argv[3]
    only = sys.argv[4].split(",") if len(sys.argv) > 4 else None
    os.makedirs(work, exist_ok=True)
    ui_marks = {}
    marks_path = os.path.join(raw, "blind-ui.json")
    if os.path.exists(marks_path):
        with open(marks_path) as handle:
            ui_marks = {m["test"]: m["start"] for m in json.load(handle) if "start" in m}
    segments = []
    starts = []
    t = 0.0
    for i, seg in enumerate(TIMELINE):
        starts.append(t)
        t += seg["dur"] - XFADE
        if only and seg["name"] not in only:
            segments.append(os.path.join(work, f"seg{i:02d}-{seg['name']}.mp4"))
            continue
        segments.append(render_segment(seg, i, raw, work, ui_marks))
        print(f"segment {i:02d} {seg['name']:<10} at {starts[-1]:6.2f}s  {seg['dur']:.1f}s")
    total = t + XFADE
    if only and "all" not in only:
        return
    # Crossfade the segments into one picture.
    inputs = []
    for p in segments:
        inputs += ["-i", p]
    chain, current = [], "[0:v]"
    for k in range(1, len(segments)):
        offset = starts[k]
        chain.append(f"{current}[{k}:v]xfade=transition=fade:duration={XFADE}:offset={offset:.3f}[x{k}]")
        current = f"[x{k}]"
    picture = os.path.join(work, "picture.mp4")
    run(
        ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(chain), "-map", current,
         "-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
         "-profile:v", "high", "-movflags", "+faststart", picture]
    )
    cues = []
    blind_from = blind_to = total
    for seg, start in zip(TIMELINE, starts):
        for at, kind in seg.get("cues", []):
            cues.append((start + at, kind))
        if seg["name"] == "blind":
            blind_from = start
        if seg["name"] == "end":
            blind_to = start
    wav = os.path.join(work, "soundtrack.wav")
    soundtrack(cues, total, blind_from, blind_to, wav)
    run(
        ["ffmpeg", "-v", "error", "-y", "-i", picture, "-i", wav, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-shortest", "-movflags", "+faststart", out]
    )
    with open(os.path.join(work, "timeline.json"), "w") as handle:
        json.dump([{"name": s["name"], "start": round(st, 2), "dur": s["dur"]} for s, st in zip(TIMELINE, starts)], handle, indent=2)
    print(f"wrote {out}: {total:.2f}s")


if __name__ == "__main__":
    main()

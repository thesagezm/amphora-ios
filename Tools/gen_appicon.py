#!/usr/bin/env python3
"""Generate Amphora's 1024x1024 app icon (Amphora/Assets.xcassets/AppIcon.appiconset/AppIcon.png).

Pure Pillow: draws at 4x and downsamples for antialiasing. Output is opaque RGB
(iOS app icons must not carry alpha — iOS applies the rounded-squircle mask).
All layering goes through alpha_composite (src over dest); every gradient is an
analytic per-pixel map (rotate()/paste() of gradient tiles leave border seams).

    python3 Tools/gen_appicon.py
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Amphora/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

S = 4096          # supersampled canvas
FINAL = 1024      # delivered size
CX = S / 2

# --- palette -----------------------------------------------------------------
BG_TOP = (66, 46, 128)       # #422E80  violet, top-left
BG_BOTTOM = (12, 8, 26)      # #0C081A  near-black, bottom-right
GLOW = (238, 175, 72)        # #EEAF48  warm halo behind the vase
GOLD_TOP = (252, 226, 148)   # #FCE294
GOLD_DEEP = (172, 116, 34)   # #AC7422
NOTE_TOP = (255, 246, 214)   # #FFF6D6  notes, bright end
NOTE_DEEP = (238, 201, 128)  # #EEC980  notes, shaded end


def u(v):  # 1024-icon units -> supersampled px
    return v * S / 1024


# --- layering helpers (src-over) ----------------------------------------------
def canvas(color):
    return Image.new("RGBA", (S, S), color + (255,))


def overlay(base, color, alpha_L):
    """Composite a solid-color layer with the given L-mode alpha over base."""
    layer = Image.new("RGBA", (S, S), color + (255,))
    layer.putalpha(alpha_L)
    return Image.alpha_composite(base, layer)


# Gradients are computed analytically per-pixel at low res and upscaled.
BASE = 512


def linear_gradient(angle_deg):
    """L image: 0 at the light corner -> 255 at the opposite corner.
    angle 0 = top->bottom, 45 = top-left light / bottom-right dark, 90 = left->right."""
    rad = math.radians(angle_deg)
    dx, dy = math.sin(rad), math.cos(rad)          # direction of increasing value
    img = Image.new("L", (BASE, BASE))
    put = img.putpixel
    corners = [(0, 0), (BASE - 1, 0), (0, BASE - 1), (BASE - 1, BASE - 1)]
    projs = [x * dx + y * dy for x, y in corners]
    lo, hi = min(projs), max(projs)
    span = hi - lo or 1
    for y in range(BASE):
        for x in range(BASE):
            put((x, y), int(255 * ((x * dx + y * dy) - lo) / span))
    return img.resize((S, S), Image.BILINEAR)


def radial_alpha(cx, cy, radius, peak=255, gamma=1.6):
    """Full-canvas L image: peak at (cx, cy) fading to 0 at radius (icon units)."""
    img = Image.new("L", (BASE, BASE))
    put = img.putpixel
    cx_b, cy_b, r_b = cx * BASE / 1024, cy * BASE / 1024, radius * BASE / 1024
    for y in range(BASE):
        for x in range(BASE):
            d = math.hypot(x - cx_b, y - cy_b)
            put((x, y), int(max(0.0, 1.0 - d / r_b) ** gamma * peak))
    return img.resize((S, S), Image.BILINEAR)


def vignette(strength=60, radius=690):
    """0 in the center -> strength at the corners."""
    inner = radial_alpha(512, 512, radius, peak=255, gamma=1.0)
    return inner.point(lambda v: (255 - v) * strength // 255)


# --- shape helpers -------------------------------------------------------------
def catmull_rom(points, samples=28):
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(len(pts) - 3):
        p0, p1, p2, p3 = pts[i:i + 4]
        for j in range(samples):
            t = j / samples
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(tuple(points[-1]))
    return out


def quad_bezier(p0, p1, p2, samples=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / samples for i in range(samples + 1))]


def stamp(drw, path, r):
    """Stamp disks along a path (round caps everywhere)."""
    for x, y in path:
        drw.ellipse((x - r, y - r, x + r, y + r), fill=255)


def rotated(points, deg, cx=0.5, cy=0.5):
    """Rotate unit-square local coords about their center; y grows down."""
    rad = math.radians(deg)
    c, s = math.cos(rad), math.sin(rad)
    return [((x - cx) * c - (y - cy) * s + cx,
             (x - cx) * s + (y - cy) * c + cy) for x, y in points]


def placed(points, cx, cy, scale):
    """Map unit-square local coords into the icon: center (cx, cy), size scale."""
    return [(u(cx + (x - 0.5) * scale), u(cy + (y - 0.5) * scale)) for x, y in points]


def note_pair_mask(cx, cy, scale, tilt_deg):
    """Beamed eighth-note pair (all-round forms: circle heads, round-capped stems/beam)."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    r_head, r_stem = 0.115, 0.034
    heads = [(0.13, 0.87), (0.66, 0.87)]
    stems = [((0.22, 0.83), (0.22, 0.24)), ((0.75, 0.83), (0.75, 0.18))]
    beam = [(0.22, 0.24), (0.75, 0.18), (0.75, 0.40), (0.22, 0.48)]

    pts = lambda lst: placed(rotated(lst, tilt_deg), cx, cy, scale)
    for hx, hy in pts(heads):
        r = u(scale * r_head)
        d.ellipse((hx - r, hy - r, hx + r, hy + r), fill=255)
    ends = pts([p for stem in stems for p in stem])   # flat [a1, b1, a2, b2]
    for a, b in zip(ends[::2], ends[1::2]):
        n = 24
        seg = [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]
        stamp(d, seg, u(scale * r_stem))
    quad = pts(beam)
    d.polygon(quad, fill=255)
    r = u(scale * r_stem)
    stamp(d, quad, r)
    return m


def single_note_mask(cx, cy, scale, tilt_deg):
    """One eighth note: round head, round stem, curved flag."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    head = [(0.42, 0.88)]
    stem = ((0.53, 0.84), (0.53, 0.12))
    flag = quad_bezier((0.53, 0.12), (0.88, 0.26), (0.78, 0.52), samples=32)

    head_p = placed(rotated(head, tilt_deg), cx, cy, scale)
    (a, b), flag_p = placed(rotated([stem[0], stem[1]], tilt_deg), cx, cy, scale), \
        placed(rotated(flag, tilt_deg), cx, cy, scale)
    r = u(scale * 0.115)
    d.ellipse((head_p[0][0] - r, head_p[0][1] - r, head_p[0][0] + r, head_p[0][1] + r), fill=255)
    n = 26
    seg = [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]
    stamp(d, seg, u(scale * 0.038))
    stamp(d, flag_p, u(scale * 0.058))
    return m


# --- 1. background ------------------------------------------------------------
bg = canvas(BG_TOP)
bg = overlay(bg, BG_BOTTOM, linear_gradient(45))
bg = overlay(bg, GLOW, radial_alpha(512, 470, 470, peak=48).filter(ImageFilter.GaussianBlur(30)))

# --- 2. sound ripples rising from the mouth -------------------------------------
d_bg = Image.new("L", (S, S), 0)
drw = ImageDraw.Draw(d_bg)
mouth = (512, 172)
for radius, alpha in ((115, 30), (165, 24), (220, 17)):
    arc = []
    for a_deg in range(-62, 63, 2):
        a = math.radians(a_deg - 90)          # -90 = straight up
        arc.append((u(mouth[0] + radius * math.cos(a)), u(mouth[1] + radius * math.sin(a))))
    faded = Image.new("L", (S, S), 0)
    stamp(ImageDraw.Draw(faded), arc, u(5))
    faded = faded.point(lambda v, A=alpha: v * A // 255)
    d_bg = ImageChops.lighter(d_bg, faded)
bg = overlay(bg, (255, 224, 158), d_bg)

# --- 3. vase fill ----------------------------------------------------------------
vase = Image.new("RGB", (S, S), GOLD_TOP)
deep = Image.new("RGB", (S, S), GOLD_DEEP)
deep.putalpha(linear_gradient(0))
vase = Image.alpha_composite(vase.convert("RGBA"), deep).convert("RGB")

# lit from the left: darker to the right, plus a warm bounce on the right edge
shade = linear_gradient(90).point(lambda v: v * 105 // 255)
vase = overlay(vase.convert("RGBA"), (40, 24, 5), shade).convert("RGB")

# broad sheen on the left shoulder + a compact specular highlight
vase = overlay(vase.convert("RGBA"), (255, 242, 196), radial_alpha(255, 425, 270, peak=76)).convert("RGB")
vase = overlay(vase.convert("RGBA"), (255, 251, 231), radial_alpha(350, 398, 80, peak=120, gamma=2.0)).convert("RGB")

# --- 4. vase silhouette ----------------------------------------------------------
PROFILE = [
    (180, 150),  # lip flare
    (215, 118),  # lip underside
    (270, 78),   # neck
    (330, 95),
    (420, 185),  # shoulder
    (520, 205),  # belly max
    (640, 175),
    (740, 105),
    (800, 72),   # stem
    (815, 88),
    (860, 125),  # foot
]

profile = [(CX + u(hw), u(y)) for y, hw in PROFILE]
right = catmull_rom(profile, samples=30)
left = [(CX - (x - CX), y) for x, y in reversed(right)]

top_cap = quad_bezier((CX - u(150), u(180)), (CX, u(148)), (CX + u(150), u(180)))
bottom_cap = quad_bezier((CX + u(125), u(860)), (CX, u(876)), (CX - u(125), u(860)))

outline = top_cap + right + bottom_cap + left

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon([(x, y) for x, y in outline], fill=255)

# handles: stamped disks along splines from rim to shoulder
for side in (1, -1):
    ctrl = [(CX + side * u(x), u(y)) for x, y in
            [(112, 242), (225, 300), (252, 415), (180, 500)]]
    stamp(ImageDraw.Draw(mask), catmull_rom(ctrl, samples=60), u(17))

# rim light hugging the lip's top edge (inside the silhouette)
rim_light = Image.new("L", (S, S), 0)
stamp(ImageDraw.Draw(rim_light), [(x, y + u(9)) for x, y in top_cap], u(7))
vase = overlay(vase.convert("RGBA"), (255, 250, 226), rim_light.point(lambda v: v * 130 // 255)).convert("RGB")

# dark rim along the whole silhouette for definition
inner = mask.filter(ImageFilter.GaussianBlur(u(7)))
rim = ImageChops.subtract(mask, inner).point(lambda v: v * 70 // 255)
vase = overlay(vase.convert("RGBA"), (46, 27, 3), rim).convert("RGB")

# --- 5. ground shadow + vase composite -------------------------------------------
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).ellipse((CX - u(160), u(858), CX + u(160), u(912)), fill=80)
shadow = shadow.filter(ImageFilter.GaussianBlur(u(14)))
icon = overlay(bg, (0, 0, 0), shadow)

vase_layer = vase.convert("RGBA")
vase_layer.putalpha(mask)
icon = Image.alpha_composite(icon, vase_layer)

# warm bounce light on the ground under the vase
icon = overlay(icon, (216, 150, 60), radial_alpha(512, 880, 190, peak=34))

# --- 6. musical notes floating out of the mouth -----------------------------------
# glow behind each note first, then the notes themselves
for (cx, cy, r, peak) in ((585, 135, 165, 90), (408, 178, 100, 55)):
    icon = overlay(icon, (255, 208, 118), radial_alpha(cx, cy, r, peak=peak))

notes_fill = Image.new("RGB", (S, S), NOTE_TOP)
deep_note = Image.new("RGB", (S, S), NOTE_DEEP)
deep_note.putalpha(linear_gradient(0))
notes_fill = Image.alpha_composite(notes_fill.convert("RGBA"), deep_note).convert("RGB")

pair = note_pair_mask(585, 135, 235, tilt_deg=-12)
single = single_note_mask(408, 178, 115, tilt_deg=9).point(lambda v: v * 88 // 255)
notes_mask = ImageChops.lighter(pair, single)

notes_layer = notes_fill.convert("RGBA")
notes_layer.putalpha(notes_mask)
icon = Image.alpha_composite(icon, notes_layer)

# sparkles around the notes
for (sx, sy, r) in ((330, 102, 8), (500, 55, 10), (688, 208, 7), (652, 92, 5)):
    icon = overlay(icon, (255, 226, 150), radial_alpha(sx, sy, r * 5, peak=58))
    sp = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sp).ellipse((u(sx - r), u(sy - r), u(sx + r), u(sy + r)), fill=235)
    icon = overlay(icon, (255, 249, 226), sp)

# --- 7. vignette + final polish ----------------------------------------------------
icon = overlay(icon, (0, 0, 0), vignette(strength=64, radius=660))

final = icon.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)
final = ImageEnhance.Sharpness(final).enhance(1.18)
final = ImageEnhance.Contrast(final).enhance(1.045)
final = ImageEnhance.Color(final).enhance(1.07)

OUT.parent.mkdir(parents=True, exist_ok=True)
final.save(OUT, "PNG")
print(f"wrote {OUT} {final.size} mode={final.mode}")

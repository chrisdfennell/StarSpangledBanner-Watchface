#!/usr/bin/env python
"""
Generate Star Spangled Banner store / promotional art into assets/:

    hero_image.png      1440x720  -- wide banner: "STAR SPANGLED" title + watch on a scene
    cover_image.png     500x500   -- square cover: the watch on a 4th-of-July scene
    cover_image.jpg     500x500   -- JPEG twin of the cover
    app_icon_24bit.png  128x128   -- circular store icon (firework-star badge)
    app_icon_64color.png 128x128  -- same icon (separate file kept for parity)

The scene is composed from the watch face's own palette (a deep night sky, stars,
fireworks bursting over an open field ringed by a distant tree line, a waving flag,
and drifting fireflies) so the art stays on-brand, with the real watch render
(assets/screen_active.png) dropped into a drawn watch body.

Run:  python tools/gen_promo.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
RENDER = os.path.join(ASSETS, "screen_active.png")  # 454x454 round RGBA
BOLD_FONT = "C:/Windows/Fonts/segoeuib.ttf"

SS = 2  # supersample factor for the big pieces

# --- night 4th-of-July palette (mirrors StarSpangledView's night sky) ----------
SKY = [
    (0.00, (6, 8, 26)),       # deep navy zenith
    (0.35, (22, 20, 58)),     # indigo
    (0.60, (60, 44, 92)),     # dusky purple
    (0.74, (150, 84, 66)),    # warm horizon glow
    (1.00, (150, 84, 66)),
]
FIELD_TOP = 0.72  # fraction of height where the field starts

FIRE_COLORS = [
    (255, 210, 63), (255, 59, 48), (79, 155, 255), (68, 224, 106),
    (255, 90, 208), (255, 255, 255), (55, 214, 255), (255, 138, 61),
]
RED = (200, 16, 46)
WHITE = (244, 247, 255)
BLUE = (52, 87, 168)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def grad_color(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            return lerp(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
    return stops[-1][1]


def vgrad(w, h, stops):
    col = Image.new("RGB", (1, h))
    for y in range(h):
        col.putpixel((0, y), grad_color(stops, y / (h - 1)))
    return col.resize((w, h))


def draw_firework(d, cx, cy, r, color, rnd, gravity=0.35):
    """A radial burst of sparks with a hot core and a little gravity droop."""
    n = rnd.choice([18, 22, 26])
    for i in range(n):
        a = 2 * math.pi * i / n
        ex = cx + math.cos(a) * r
        ey = cy + math.sin(a) * r + r * gravity * 0.5
        # spark trail: a few fading dots from ~0.6r out to the tip
        for f, alpha in [(0.6, 90), (0.8, 150), (1.0, 230)]:
            px = cx + math.cos(a) * r * f
            py = cy + math.sin(a) * r * f + r * gravity * 0.5 * f
            rr = 2 if f > 0.9 else 1
            d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=color + (alpha,))
    # core flash
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 255, 255, 230))


def draw_rocket(d, x, y0, y1, color):
    """A rising rocket: bright head + a short fading trail."""
    d.ellipse([x - 2, y1 - 2, x + 2, y1 + 2], fill=(255, 233, 168, 235))
    for j in range(1, 5):
        ty = y1 + j * (y0 - y1) * 0.10
        a = max(40, 200 - j * 40)
        d.ellipse([x - 1, ty - 1, x + 1, ty + 1], fill=color + (a,))


def draw_treeline(d, w, base_y, h, color):
    """A silhouetted distant tree line: overlapping canopy + a few conifers."""
    r = int(w * 0.045)
    d.rectangle([0, base_y, w, base_y + int(h * 0.02) + 4], fill=color)
    i = 0
    x = -r
    step = int(r * 1.3)
    while x < w + r:
        rr = r + ((i % 3) - 1) * (r // 4)
        top = base_y - int(rr * 0.7)
        d.ellipse([x - rr, top - rr, x + rr, top + rr], fill=color)
        if i % 4 == 2:
            ch = int(r * 2.2)
            cw = int(r * 0.7)
            d.polygon([(x - cw, base_y - int(r * 0.4)),
                       (x + cw, base_y - int(r * 0.4)),
                       (x, base_y - ch)], fill=color)
        x += step
        i += 1


def draw_flag(d, px, base_y, ph, w):
    """A small waving American flag on a pole, planted in the field."""
    top_y = base_y - ph
    pw = max(2, int(ph * 0.025))
    d.rectangle([px - pw, top_y, px + pw, base_y], fill=(154, 160, 166))
    d.ellipse([px - pw * 1.6, top_y - pw * 1.6, px + pw * 1.6, top_y + pw * 1.6], fill=(255, 210, 63))

    fw = int(ph * 0.55)
    fh = int(ph * 0.36)
    fx = px + pw
    stripe_h = fh / 13.0
    slices = 26
    sw = fw / slices
    union_slices = int(slices * 0.40)
    for s in range(slices):
        xs = fx + s * sw
        dy = (fh * 0.12) * (s / slices) * math.sin(s * 0.5)
        for st in range(13):
            y0 = top_y + st * stripe_h + dy
            if s < union_slices and st < 7:
                col = BLUE
            else:
                col = RED if st % 2 == 0 else WHITE
            d.rectangle([xs, y0, xs + sw + 1, y0 + stripe_h + 1], fill=col)
    # star dots in the canton
    uw = union_slices * sw
    uh = 7 * stripe_h
    for ry in range(3):
        for cxs in range(4):
            sx = fx + uw * (cxs + 0.7) / 4.4
            sy = top_y + uh * (ry + 0.7) / 3.4
            d.ellipse([sx - 1, sy - 1, sx + 1, sy + 1], fill=WHITE)


def build_scene(w, h):
    """Return an RGB 4th-of-July night scene sized (w, h)."""
    rnd = random.Random(76)
    img = vgrad(w, h, SKY)
    d = ImageDraw.Draw(img, "RGBA")
    field_y = int(h * FIELD_TOP)

    # stars (upper sky only)
    for _ in range(int(w * h / 4200)):
        x = rnd.randint(0, w - 1)
        y = rnd.randint(0, int(field_y * 0.78))
        r = rnd.choice([1, 1, 1, 2])
        a = rnd.randint(110, 235)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))

    # fireworks (blurred glow layer + crisp sparks)
    fw_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fw_layer)
    bursts = [
        (0.20, 0.26, 0.13), (0.40, 0.16, 0.10), (0.62, 0.30, 0.15),
        (0.80, 0.20, 0.11), (0.30, 0.40, 0.08), (0.72, 0.46, 0.09),
    ]
    for fx, fy, fr in bursts:
        draw_firework(fd, int(w * fx), int(h * fy), int(w * fr),
                      rnd.choice(FIRE_COLORS), rnd)
    glow = fw_layer.filter(ImageFilter.GaussianBlur(h * 0.012))
    img.paste(glow, (0, 0), glow)
    img.paste(fw_layer, (0, 0), fw_layer)

    # a couple of rising rockets
    for rx, c in [(0.50, (255, 210, 63)), (0.88, (255, 90, 208))]:
        draw_rocket(d, int(w * rx), int(field_y * 0.98), int(field_y * 0.66), c)

    # distant tree line on the horizon
    draw_treeline(d, w, field_y, h, (12, 36, 20))

    # rolling field (two green bands), darker for night
    for layer, (off, col) in enumerate([(0, (22, 54, 30)), (int(h * 0.05), (16, 42, 24))]):
        pts = [(0, h)]
        for xi in range(0, w + 1, max(2, w // 90)):
            yy = field_y + off + math.sin(xi / w * math.pi * 3 + layer) * h * 0.012
            pts.append((xi, yy))
        pts.append((w, h))
        d.polygon(pts, fill=col)
    # foreground grass strip
    d.rectangle([0, int(h * 0.92), w, h], fill=(10, 30, 18))

    # waving flag planted to the right
    draw_flag(d, int(w * 0.84), int(field_y + h * 0.10), int(h * 0.26), w)

    # fireflies low over the field
    for _ in range(int(w * h / 9000)):
        x = rnd.randint(0, w - 1)
        y = rnd.randint(field_y, h - 1)
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(42, 58, 18, 150))
        d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(216, 240, 96, 235))
    return img


def paste_watch(scene, cx, cy, screen_d):
    """Draw a watch body and drop the real round render onto it, centred at (cx, cy)."""
    w, h = scene.size
    render = Image.open(RENDER).convert("RGBA").resize((screen_d, screen_d), Image.LANCZOS)
    case_d = int(screen_d * 1.13)
    band_w = int(case_d * 0.46)

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # contact shadow on the field
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - case_d * 0.55, cy + case_d * 0.30,
                                cx + case_d * 0.55, cy + case_d * 0.62],
                               fill=(4, 10, 6, 130))
    sh = sh.filter(ImageFilter.GaussianBlur(case_d * 0.04))
    scene.paste(sh, (0, 0), sh)

    # band (top + bottom)
    for sign in (-1, 1):
        y0 = cy + sign * case_d * 0.30
        y1 = cy + sign * case_d * 0.95
        top, bot = (y0, y1) if sign < 0 else (y1, y0)
        d.polygon([(cx - band_w / 2, cy), (cx + band_w / 2, cy),
                   (cx + band_w * 0.40, bot if sign > 0 else top),
                   (cx - band_w * 0.40, bot if sign > 0 else top)],
                  fill=(28, 30, 38, 255))
    # case
    d.ellipse([cx - case_d / 2, cy - case_d / 2, cx + case_d / 2, cy + case_d / 2],
              fill=(20, 21, 27, 255))
    # bezel ring
    bz = int(screen_d * 1.05)
    d.ellipse([cx - bz / 2, cy - bz / 2, cx + bz / 2, cy + bz / 2],
              outline=(74, 78, 90, 255), width=max(2, int(screen_d * 0.012)))
    scene.paste(layer, (0, 0), layer)

    # metallic sheen arc on the case (top-left)
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).arc([cx - case_d / 2, cy - case_d / 2, cx + case_d / 2, cy + case_d / 2],
                              start=160, end=250, fill=(190, 195, 215, 150),
                              width=max(2, int(case_d * 0.02)))
    sheen = sheen.filter(ImageFilter.GaussianBlur(case_d * 0.01))
    scene.paste(sheen, (0, 0), sheen)

    # the actual round render (its own alpha makes it a clean circle)
    scene.paste(render, (cx - screen_d // 2, cy - screen_d // 2), render)


def draw_title(scene, text, cx, cy, px):
    """Centred, letter-spaced bold title with a navy shadow + warm gold glow."""
    font = ImageFont.truetype(BOLD_FONT, px)
    track = int(px * 0.10)
    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] for ch in text]
    total = sum(widths) + track * (len(text) - 1)
    asc, desc = font.getmetrics()

    glow = Image.new("RGBA", scene.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    x = cx - total / 2
    y = cy - (asc + desc) / 2
    for ch, wch in zip(text, widths):
        gd.text((x, y), ch, font=font, fill=(255, 210, 100, 255))
        x += wch + track
    glow = glow.filter(ImageFilter.GaussianBlur(px * 0.11))
    scene.paste(glow, (0, 0), glow)

    d = ImageDraw.Draw(scene)
    x = cx - total / 2
    for ch, wch in zip(text, widths):
        d.text((x + px * 0.03, y + px * 0.03), ch, font=font, fill=(18, 18, 40))  # shadow
        d.text((x, y), ch, font=font, fill=(244, 247, 255))                       # face
        x += wch + track


def star_badge(size):
    """A red/white/blue firework-star badge -> RGBA (size x size)."""
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    badge = vgrad(S, S, [(0.0, (10, 14, 40)), (0.6, (24, 30, 80)),
                         (1.0, (44, 54, 120))]).convert("RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([S * 0.02, S * 0.02, S * 0.98, S * 0.98], fill=255)
    img.paste(badge, (0, 0), mask)
    d.ellipse([S * 0.02, S * 0.02, S * 0.98, S * 0.98], outline=(255, 210, 63, 235),
              width=max(2, int(S * 0.03)))

    cx = cy = S / 2
    # firework rays in red / white / blue
    cols = [(224, 58, 58), (244, 247, 255), (79, 123, 232)]
    for k in range(12):
        a = math.radians(30 * k - 90)
        r1, r2 = S * 0.12, S * 0.40
        d.line([(cx + math.cos(a) * r1, cy + math.sin(a) * r1),
                (cx + math.cos(a) * r2, cy + math.sin(a) * r2)],
               fill=cols[k % 3] + (255,), width=max(2, int(S * 0.022)))
        tx, ty = cx + math.cos(a) * r2, cy + math.sin(a) * r2
        d.ellipse([tx - S * 0.02, ty - S * 0.02, tx + S * 0.02, ty + S * 0.02],
                  fill=cols[k % 3] + (255,))

    # central white five-point star
    pts = []
    for i in range(10):
        rad = S * 0.16 if i % 2 == 0 else S * 0.067
        ang = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.ellipse([cx - S * 0.03, cy - S * 0.03, cx + S * 0.03, cy + S * 0.03], fill=(255, 243, 192, 255))
    return img.resize((size, size), Image.LANCZOS)


def build_hero():
    W, H = 1440 * SS, 720 * SS
    scene = build_scene(W, H)
    paste_watch(scene, int(W * 0.50), int(H * 0.56), int(H * 0.60))
    draw_title(scene, "STAR SPANGLED", int(W * 0.50), int(H * 0.135), int(H * 0.110))
    return scene.resize((1440, 720), Image.LANCZOS)


def build_cover():
    W = H = 500 * SS
    scene = build_scene(W, H)
    paste_watch(scene, W // 2, int(H * 0.50), int(H * 0.66))
    return scene.resize((500, 500), Image.LANCZOS)


if __name__ == "__main__":
    hero = build_hero()
    hero.save(os.path.join(ASSETS, "hero_image.png"))
    print("hero_image.png      1440x720")

    cover = build_cover()
    cover.save(os.path.join(ASSETS, "cover_image.png"))
    cover.convert("RGB").save(os.path.join(ASSETS, "cover_image.jpg"), quality=90)
    print("cover_image.png/.jpg 500x500")

    icon = star_badge(128)
    icon.convert("RGB").save(os.path.join(ASSETS, "app_icon_24bit.png"))
    icon.convert("RGB").save(os.path.join(ASSETS, "app_icon_64color.png"))
    print("app_icon_*.png      128x128")
    print("Done.")

#!/usr/bin/env python3
"""Zeichnet das App-Icon (1024 px) und erzeugt app/AppIcon.icns.  Benötigt: Pillow."""
import os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4096                     # 4x supersampling, am Ende auf 1024 verkleinert
HERE = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size, index=index)
    except OSError:
        return ImageFont.load_default()


def bubble(draw, box, tail, fill, r):
    draw.rounded_rectangle(box, radius=r, fill=fill)
    draw.polygon(tail, fill=fill)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Grundfläche: macOS-Icon-Raster (824/1024) mit diagonalem Verlauf Blau -> Orange
    m = int(S * 100 / 1024)
    body = (m, m, S - m, S - m)
    grad = Image.new("RGB", (S, S))
    gp = grad.load()
    c1, c2, c3 = (37, 99, 235), (124, 58, 237), (245, 140, 30)
    step = 16
    gd = ImageDraw.Draw(grad)
    for y in range(0, S, step):
        for x in range(0, S, step):
            t = (x + y) / (2 * S)
            col = lerp(c1, c2, t / 0.5) if t < 0.5 else lerp(c2, c3, (t - 0.5) / 0.5)
            gd.rectangle((x, y, x + step, y + step), fill=col)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius=int(S * 185 / 1024), fill=255)

    # weicher Schatten unter der Fläche
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((body[0], body[1] + 40, body[2], body[3] + 40),
                                             radius=int(S * 185 / 1024), fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(60)))
    img.paste(grad, (0, 0), mask)

    # dezenter Glanz oben
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse((-S * 0.2, -S * 0.75, S * 1.2, S * 0.42), fill=(255, 255, 255, 34))
    gl_mask = Image.new("L", (S, S), 0); gl_mask.paste(mask)
    img = Image.alpha_composite(img, Image.composite(gloss, Image.new("RGBA", (S, S)), gl_mask))

    d = ImageDraw.Draw(img)
    u = S / 1024

    # linke Sprechblase (Englisch) – weiß
    lb = (205 * u, 250 * u, 610 * u, 560 * u)
    bubble(d, lb, [(280 * u, 540 * u), (250 * u, 650 * u), (380 * u, 545 * u)], (255, 255, 255, 255), 90 * u)
    # rechte Sprechblase (Thai) – dunkel, leicht überlappend
    rb = (415 * u, 470 * u, 820 * u, 780 * u)
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((rb[0], rb[1] + 18 * u, rb[2], rb[3] + 18 * u), radius=90 * u, fill=(0, 0, 0, 90))
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(30 * u)))
    d = ImageDraw.Draw(img)
    bubble(d, rb, [(745 * u, 760 * u), (775 * u, 870 * u), (640 * u, 765 * u)], (24, 24, 40, 255), 90 * u)

    # Schrift: "Hi" (EN) und "ก" (erster Buchstabe des Thai-Alphabets)
    latin = font("/System/Library/Fonts/HelveticaNeue.ttc", int(230 * u), index=1)
    thai = font("/System/Library/Fonts/Supplemental/Thonburi.ttc", int(250 * u), index=1)
    d.text(((lb[0] + lb[2]) / 2, (lb[1] + lb[3]) / 2 - 30 * u), "Hi", font=latin, fill=(37, 99, 235), anchor="mm")
    d.text(((rb[0] + rb[2]) / 2, (rb[1] + rb[3]) / 2 + 10 * u), "ก",
           font=thai, fill=(255, 170, 60), anchor="mm")

    # kleine Schallwellen oben rechts = "spricht"
    for i, rr in enumerate((70, 115, 160)):
        cx, cy = 690 * u, 330 * u
        d.arc((cx - rr * u, cy - rr * u, cx + rr * u, cy + rr * u), start=-60, end=20,
              fill=(255, 255, 255, 230 - i * 55), width=int(22 * u))

    icon = img.resize((1024, 1024), Image.LANCZOS)
    icon.save(os.path.join(HERE, "icon_1024.png"))

    with tempfile.TemporaryDirectory() as td:
        iconset = os.path.join(td, "AppIcon.iconset")
        os.makedirs(iconset)
        for sz in (16, 32, 128, 256, 512):
            icon.resize((sz, sz), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}.png")
            icon.resize((sz * 2, sz * 2), Image.LANCZOS).save(f"{iconset}/icon_{sz}x{sz}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(HERE, "AppIcon.icns")], check=True)
    print("✓ app/AppIcon.icns")


if __name__ == "__main__":
    main()

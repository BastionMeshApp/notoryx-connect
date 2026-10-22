"""Regenerates the launcher icons and Play Store graphics from the source art.

Run from the repository root on macOS (uses system fonts): python3 tool/make_store_graphics.py
Requires Pillow (pip install pillow).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SOURCE = Path('branding/notoryx-icon-source.png')
BRANDING = Path('branding')
PLAY = Path('fastlane/metadata/android/en-US/images')
FONTS = Path('/System/Library/Fonts')

art = Image.open(SOURCE).convert('RGB')
W = art.width


def average(box):
    px = list(art.crop(box).getdata())
    return tuple(sum(c[i] for c in px) // len(px) for i in range(3))


background = average((0, 0, 24, 24))       # #101011, the adaptive background
orange = average((int(W * .68), int(W * .24), int(W * .78), int(W * .33)))

# Full framed tile: older launchers and the Play icon.
art.resize((1024, 1024), Image.LANCZOS).save(BRANDING / 'notoryx-icon.png')
art.resize((512, 512), Image.LANCZOS).save(PLAY / 'icon.png')

# Adaptive foreground: the N mark without the frame, feathered so it blends
# into the background, sized to stay inside the circle safe zone.
mark = art.crop((int(W * .165), int(W * .17), int(W * .835), int(W * .84)))
size = 480
mark = mark.resize((size, size), Image.LANCZOS)
alpha = Image.new('L', (size, size), 0)
ImageDraw.Draw(alpha).rounded_rectangle((24, 24, size - 24, size - 24), 52, fill=255)
mark.putalpha(alpha.filter(ImageFilter.GaussianBlur(15)))
foreground = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
foreground.alpha_composite(mark, ((1024 - size) // 2,) * 2)
foreground.save(BRANDING / 'notoryx-icon-foreground.png')

# Feature graphic, 1024 x 500.
graphic = Image.new('RGB', (1024, 500), background)
graphic.paste(art.resize((400, 400), Image.LANCZOS), (50, 50))
draw = ImageDraw.Draw(graphic)
title = ImageFont.truetype(str(FONTS / 'Supplemental/DIN Condensed Bold.ttf'), 128)
sub = ImageFont.truetype(str(FONTS / 'Supplemental/DIN Condensed Bold.ttf'), 60)
tagline = ImageFont.truetype(str(FONTS / 'Avenir Next.ttc'), 34)
x = 490
draw.text((x, 96), 'NOTORYX', font=title, fill=(236, 236, 236))
cx = x + 4
for ch in 'CONNECT':
    draw.text((cx, 222), ch, font=sub, fill=orange)
    cx += draw.textlength(ch, font=sub) + 14
draw.line((x + 4, 312, 960, 312), fill=orange, width=3)
draw.text((x + 4, 334), 'No Towers. No Limits.', font=tagline, fill=(190, 190, 190))
graphic.save(PLAY / 'featureGraphic.png')
print('background #%02X%02X%02X, orange #%02X%02X%02X' % (background + orange))

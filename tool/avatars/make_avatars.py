#!/usr/bin/env python3
"""Turns the avatar artwork (a black disc in a gold ring, on a white or black background,
sometimes slightly oval) into round transparent PNGs for the app, and a contact sheet.

    python3 tool/avatars/make_avatars.py <artwork folder> [preview.png]

Writes assets/avatars/<name>.png (256 px) and rewrites kAvatarArt in lib/app/avatars.dart.
"""
import glob
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Picker order: file name prefix -> asset name.
ART = [
    ('4304fedd', 'punk_pig'), ('8e080148', 'wizard_cow'), ('e010da8e', 'dog_white_hat'),
    ('5dc4b3f5', 'grumpy_cat'), ('f82bbc13', 'sun'), ('e4614c2c', 'sleepy_moon'),
    ('0a8c5e7d', 'horse_carrot'), ('7b32178b', 'sunflower'), ('aec079fa', 'coffee_mug'),
    ('02f1f264', 'skull'), ('6839d5a4', 'ghost'), ('515a5e64', 'raccoon'),
    ('f6417e61', 'parrot'), ('54f444a2', 'fox'), ('6ffcecf5', 'hamster'), ('3a8fcbd9', 'cactus'),
]
SIZE = 256
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def ring_box(img):
    """Bounding box of the gold ring: gold-ish pixels (warm, saturated, bright enough), keeping
    only rows/columns with a few of them so stray specks don't count."""
    a = np.asarray(img.convert('RGB')).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    gold = (r > 110) & (r - b > 45) & (g > 70) & (r >= g)
    rows = np.where(gold.sum(axis=1) >= 3)[0]
    cols = np.where(gold.sum(axis=0) >= 3)[0]
    return cols.min(), rows.min(), cols.max() + 1, rows.max() + 1


def make(src, dst):
    img = Image.open(src).convert('RGB')
    box = ring_box(img)
    # Stretch an oval ring to a circle, at 4x for a smooth edge.
    big = img.crop(box).resize((SIZE * 4, SIZE * 4), Image.LANCZOS)
    mask = Image.new('L', big.size, 0)
    ImageDraw.Draw(mask).ellipse((2, 2, big.size[0] - 3, big.size[1] - 3), fill=255)
    out = big.convert('RGBA')
    out.putalpha(mask)
    out = out.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(dst, optimize=True)
    return out


def main():
    src_dir = sys.argv[1]
    preview = sys.argv[2] if len(sys.argv) > 2 else None
    out_dir = os.path.join(ROOT, 'assets', 'avatars')
    os.makedirs(out_dir, exist_ok=True)
    made = []
    for prefix, name in ART:
        files = glob.glob(os.path.join(src_dir, prefix + '*.jpg')) + glob.glob(os.path.join(src_dir, prefix + '*.png'))
        if not files:
            print('missing', prefix, name)
            continue
        made.append((name, make(files[0], os.path.join(out_dir, name + '.png'))))
    # The app's list, in picker order.
    p = os.path.join(ROOT, 'lib', 'app', 'avatars.dart')
    s = open(p).read()
    items = ''.join(f"  'assets/avatars/{n}.png',\n" for n, _ in made)
    s = re.sub(r"(const kAvatarArt = <String>\[\n  // [^\n]*\n)(.*?)(\];)", lambda m: m.group(1) + items + m.group(3), s, flags=re.S)
    open(p, 'w').write(s)
    if preview and made:
        cols, cell, pad = 4, 200, 16
        rows = (len(made) + cols - 1) // cols
        sheet = Image.new('RGBA', (cols * (cell + pad) + pad, rows * (cell + 40 + pad) + pad), (40, 22, 14, 255))
        d = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'Rubik.ttf'), 18)
        except OSError:
            font = ImageFont.load_default()
        for i, (name, im) in enumerate(made):
            x, y = pad + (i % cols) * (cell + pad), pad + (i // cols) * (cell + 40 + pad)
            sheet.alpha_composite(im.resize((cell, cell), Image.LANCZOS), (x, y))
            d.text((x + cell / 2, y + cell + 8), name.replace('_', ' '), fill=(250, 224, 150, 255), font=font, anchor='mt')
        sheet.save(preview)
    print('made', len(made))


if __name__ == '__main__':
    main()

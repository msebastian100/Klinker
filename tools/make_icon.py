#!/usr/bin/env python3
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
s = 1024
im = Image.new("RGB", (s, s), "#1D76F9")
d = ImageDraw.Draw(im)
d.rounded_rectangle([78, 118, 946, 930], radius=48, fill="#0D1753", outline="#E7F1FF", width=12)

colors = ["#F0714A", "#F0A04A", "#F0D15A", "#7ED0A0", "#7EC8F0"]
shine = ["#F7B39A", "#F7C99A", "#F7E7A4", "#C8EBD6", "#C8E6F8"]
left, top = 132, 176
bw, bh, gx, gy = 88, 46, 12, 14
for r, color in enumerate(colors):
    for c in range(8):
        x = left + c * (bw + gx)
        y = top + r * (bh + gy)
        d.rounded_rectangle([x, y, x + bw, y + bh], radius=9, fill=color)
        d.rounded_rectangle([x + 7, y + 6, x + bw - 7, y + 18], radius=4, fill=shine[r])

d.rounded_rectangle([330, 820, 694, 868], radius=24, fill="#F07A4A")
d.rounded_rectangle([368, 820, 656, 868], radius=22, fill="#F7FBFF")
d.ellipse([478, 742, 546, 810], fill="#FFFFFF")
d.ellipse([496, 754, 528, 786], fill="#FFE3C2")
im.save(out, "PNG")

#!/usr/bin/env python3
"""Draw a synthetic Spanish pizza menu (a made-up menu, not a real business's) for testing."""
from PIL import Image, ImageDraw, ImageFont
import sys
lines = [
 "PIZZAS",
 "Margarita ........ ₡7.000",
 "tomate, mozzarella y albahaca",
 "Vegetariana ........ 8500",
 "champiñones, espinaca, aceitunas y pimiento",
 "Pepperoni  Pequeña 5.000  Grande 9.000",
 "BEBIDAS",
 "Refresco natural ... 1.500",
 "Agua 1 mil",
 "Promoción del día ...... 12",
]
f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 34)
im = Image.new("RGB", (1500, 80 + 60 * len(lines) + 60), "white")
d = ImageDraw.Draw(im)
for i, t in enumerate(lines):
    d.text((50, 40 + 60 * i), t, fill="black", font=f)
# dish "photos" (coloured noise blobs, not real food) to the right of three items
import random
random.seed(3)
def photo(x, y, base):
    for _ in range(900):
        r = random.randint(8, 24)
        cx, cy = x + random.randint(25, 195), y + random.randint(25, 145)
        c = tuple(max(0, min(255, b + random.randint(-70, 70))) for b in base)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)
photo(1180, 80, (200, 60, 40))     # next to Margarita
photo(1180, 290, (80, 150, 60))    # next to Vegetariana
photo(1180, 500, (210, 150, 60))   # next to Pepperoni
im.save(sys.argv[1] if len(sys.argv) > 1 else "sample_menu.png")

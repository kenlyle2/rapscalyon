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
im = Image.new("RGB", (1500, 80 + 60 * len(lines)), "white")
d = ImageDraw.Draw(im)
for i, t in enumerate(lines):
    d.text((50, 40 + 60 * i), t, fill="black", font=f)
im.save(sys.argv[1] if len(sys.argv) > 1 else "sample_menu.png")

import math
from PIL import Image, ImageDraw
import os

def create_icon(size, draw_func, filename):
    scale = 8
    img = Image.new('RGBA', (size * scale, size * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_func(d, size * scale)
    out = img.resize((size, size), Image.Resampling.LANCZOS)
    out.save(filename, format='TGA')

# Modern, Flat, Minimalist, "The Genius" Style
# High contrast, exact geometric alignment, no inner glows or complex overlapping.
# Just thick, sleek geometric outlines and very subtle flat transparent fills.

def tank(d, s):
    # Pure hexagonal outline with a single heavy line inside (shield metaphor)
    color = (0, 255, 255) # Cyan
    cx, cy = s*0.5, s*0.5
    r = s*0.4
    points = []
    for i in range(6):
        angle = math.pi/2 + math.pi/3 * i
        points.append((cx + r*math.cos(angle), cy + r*math.sin(angle)))
    d.polygon(points, outline=color+(255,), width=s//12)
    # Inner horizontal slab
    d.line([(cx - r*0.5, cy), (cx + r*0.5, cy)], fill=color+(255,), width=s//10)
    d.polygon(points, fill=color+(40,))

def healer(d, s):
    # Extremely minimalist rotated square cross (plus sign built from diamonds/arrows)
    color = (255, 60, 200) # Bright Magenta
    # Just two thick intersecting rounded/sharp lines forming a perfect +
    v_line = [(s*0.42, s*0.15), (s*0.58, s*0.15), (s*0.58, s*0.85), (s*0.42, s*0.85)]
    h_line = [(s*0.15, s*0.42), (s*0.85, s*0.42), (s*0.85, s*0.58), (s*0.15, s*0.58)]
    # We draw them as polygons with slightly pointed ends for "Genius" sharpness
    v_sharp = [(s*0.5, s*0.1), (s*0.6, s*0.2), (s*0.6, s*0.8), (s*0.5, s*0.9), (s*0.4, s*0.8), (s*0.4, s*0.2)]
    h_sharp = [(s*0.1, s*0.5), (s*0.2, s*0.4), (s*0.8, s*0.4), (s*0.9, s*0.5), (s*0.8, s*0.6), (s*0.2, s*0.6)]
    d.polygon(v_sharp, fill=color+(40,), outline=color+(255,), width=s//15)
    d.polygon(h_sharp, fill=color+(40,), outline=color+(255,), width=s//15)
    d.polygon([(s*0.4, s*0.4), (s*0.6, s*0.4), (s*0.6, s*0.6), (s*0.4, s*0.6)], fill=color+(255,))

def dps(d, s):
    # Triple chevron (downward pointing arrows, razor sharp, futuristic)
    color = (255, 100, 0) # Intense Orange
    w = s//12
    # Arrow 1 (Top)
    d.line([(s*0.2, s*0.3), (s*0.5, s*0.55), (s*0.8, s*0.3)], fill=color+(255,), width=w, joint="miter")
    # Arrow 2 (Middle)
    d.line([(s*0.2, s*0.5), (s*0.5, s*0.75), (s*0.8, s*0.5)], fill=color+(255,), width=w, joint="miter")
    # Spear point (Bottom)
    d.polygon([(s*0.45, s*0.75), (s*0.55, s*0.75), (s*0.5, s*0.95)], fill=color+(255,))

def leader(d, s):
    # Minimalist crown: A flat thick base line and three distinct triangles
    color = (255, 200, 0) # Amber / Golden Yellow
    d.line([(s*0.2, s*0.85), (s*0.8, s*0.85)], fill=color+(255,), width=s//10)
    # Triangles
    d.polygon([(s*0.2, s*0.75), (s*0.35, s*0.75), (s*0.275, s*0.3)], fill=color+(255,))
    d.polygon([(s*0.4, s*0.75), (s*0.6, s*0.75), (s*0.5, s*0.2)], fill=color+(255,))
    d.polygon([(s*0.65, s*0.75), (s*0.8, s*0.75), (s*0.725, s*0.3)], fill=color+(255,))

def combat(d, s):
    # Diagonal racing stripes / slash marks. Extremely modern and intense.
    color = (255, 50, 50) # Red
    # Slash 1
    d.polygon([(s*0.2, s*0.9), (s*0.4, s*0.9), (s*0.8, s*0.1), (s*0.6, s*0.1)], fill=color+(255,))
    # Slash 2
    d.polygon([(s*0.45, s*0.9), (s*0.55, s*0.9), (s*0.9, s*0.1), (s*0.8, s*0.1)], fill=color+(255,))
    # Accent dot
    d.ellipse([(s*0.15, s*0.15), (s*0.35, s*0.35)], fill=color+(255,))

def rest(d, s):
    # A single, perfect geometric crescent combined with a clean dot or Z
    color = (100, 255, 100) # Bright Lime/Mint
    # Create the crescent using math
    d.arc([(s*0.1, s*0.1), (s*0.9, s*0.9)], start=110, end=340, fill=color+(255,), width=s//10)
    # The modern "Z": sleek, slanted
    d.line([(s*0.4, s*0.4), (s*0.6, s*0.4), (s*0.4, s*0.6), (s*0.6, s*0.6)], fill=color+(255,), width=s//15, joint="miter")

path = r"C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI_UF\Media\Icons"
create_icon(64, tank, os.path.join(path, "tank_polygon.tga"))
create_icon(64, healer, os.path.join(path, "healer_polygon.tga"))
create_icon(64, dps, os.path.join(path, "dps_polygon.tga"))
create_icon(64, leader, os.path.join(path, "leader_polygon.tga"))
create_icon(128, combat, os.path.join(path, "combat_polygon.tga"))
create_icon(256, rest, os.path.join(path, "rest_polygon.tga"))
print("Done")

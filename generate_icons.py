import math
from PIL import Image, ImageDraw
import os

def create_icon(size, draw_func, filename):
    scale = 4
    img = Image.new('RGBA', (size * scale, size * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_func(d, size * scale)
    out = img.resize((size, size), Image.Resampling.LANCZOS)
    out.save(filename, format='TGA')

def tank(d, s):
    points = [(s*0.5, s*0.05), (s*0.9, s*0.25), (s*0.9, s*0.75), (s*0.5, s*0.95), (s*0.1, s*0.75), (s*0.1, s*0.25)]
    d.polygon(points, fill=(10, 20, 30, 230), outline=(0, 255, 255, 255), width=s//15)
    inner = [(s*0.5, s*0.2), (s*0.75, s*0.35), (s*0.75, s*0.65), (s*0.5, s*0.8), (s*0.25, s*0.65), (s*0.25, s*0.35)]
    d.polygon(inner, fill=(0, 150, 255, 100), outline=(0, 200, 255, 200), width=s//30)

def healer(d, s):
    color = (255, 50, 150)
    w = s//3.5
    v_diamond = [(s*0.5, s*0.1), (s*0.5+w, s*0.5), (s*0.5, s*0.9), (s*0.5-w, s*0.5)]
    h_diamond = [(s*0.1, s*0.5), (s*0.5, s*0.5-w), (s*0.9, s*0.5), (s*0.5, s*0.5+w)]
    d.polygon(v_diamond, fill=(20, 10, 20, 230), outline=color+(255,), width=s//15)
    d.polygon(h_diamond, fill=(20, 10, 20, 230), outline=color+(255,), width=s//15)
    d.polygon([(s*0.5, s*0.35), (s*0.65, s*0.5), (s*0.5, s*0.65), (s*0.35, s*0.5)], fill=color+(200,))

def dps(d, s):
    color = (255, 120, 20)
    # Sharp downward spearhead/chevron
    points = [(s*0.5, s*0.95), (s*0.85, s*0.2), (s*0.5, s*0.4), (s*0.15, s*0.2)]
    d.polygon(points, fill=(30, 10, 0, 230), outline=color+(255,), width=s//15)
    points2 = [(s*0.5, s*0.7), (s*0.7, s*0.28), (s*0.5, s*0.4), (s*0.3, s*0.28)]
    d.polygon(points2, fill=color+(255,))

def leader(d, s):
    color = (255, 200, 30)
    # Crown polygon
    crown = [(s*0.2, s*0.8), (s*0.8, s*0.8), (s*0.9, s*0.3), (s*0.65, s*0.5), (s*0.5, s*0.1), (s*0.35, s*0.5), (s*0.1, s*0.3)]
    d.polygon(crown, fill=(30, 20, 0, 230), outline=color+(255,), width=s//15)
    # Inner gem
    d.polygon([(s*0.5, s*0.55), (s*0.65, s*0.65), (s*0.5, s*0.75), (s*0.35, s*0.65)], fill=color+(255,))

def combat(d, s):
    color = (255, 40, 40)
    # Two intersecting crossed blades/slashes
    blade1 = [(s*0.15, s*0.1), (s*0.25, s*0.1), (s*0.9, s*0.8), (s*0.8, s*0.9), (s*0.1, s*0.25)]
    blade2 = [(s*0.85, s*0.1), (s*0.9, s*0.25), (s*0.2, s*0.9), (s*0.1, s*0.8), (s*0.75, s*0.1)]
    d.polygon(blade1, fill=(20, 5, 5, 200), outline=color+(255,), width=s//15)
    d.polygon(blade2, fill=(20, 5, 5, 200), outline=color+(255,), width=s//15)

def rest(d, s):
    color = (50, 255, 150)
    moon = [(s*0.5, s*0.1), (s*0.8, s*0.25), (s*0.9, s*0.5), (s*0.8, s*0.75), (s*0.5, s*0.9), (s*0.2, s*0.75)]
    d.polygon(moon, fill=(10, 30, 20, 200), outline=color+(200,), width=s//20)
    z = [(s*0.3, s*0.3), (s*0.7, s*0.3), (s*0.3, s*0.7), (s*0.7, s*0.7)]
    d.line([(s*0.3, s*0.25), (s*0.6, s*0.25), (s*0.3, s*0.6), (s*0.6, s*0.6)], fill=color+(255,), width=s//15, joint="curve")

path = r"C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI_UF\Media\Icons"
create_icon(64, tank, os.path.join(path, "tank_polygon.tga"))
create_icon(64, healer, os.path.join(path, "healer_polygon.tga"))
create_icon(64, dps, os.path.join(path, "dps_polygon.tga"))
create_icon(64, leader, os.path.join(path, "leader_polygon.tga"))
create_icon(128, combat, os.path.join(path, "combat_polygon.tga"))
create_icon(256, rest, os.path.join(path, "rest_polygon.tga"))
print("Done")

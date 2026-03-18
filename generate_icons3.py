import math
from PIL import Image, ImageDraw
import os

def create_icon(size, draw_func, filename):
    scale = 12
    img = Image.new('RGBA', (size * scale, size * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_func(d, size * scale)
    out = img.resize((size, size), Image.Resampling.LANCZOS)
    out.save(filename, format='TGA')

# V3.4 - Elegant Gemstones with internal facets mapped but keeping out-lines clean

def tank(d, s):
    # Sapphire Shield (Hexagon with deep cuts)
    c_light = (80, 160, 230)
    c_base = (40, 110, 180)
    c_dark = (20, 60, 110)
    c_rim = (210, 240, 255)
    
    top = (s*0.5, s*0.1)
    t_l = (s*0.15, s*0.3)
    t_r = (s*0.85, s*0.3)
    b_l = (s*0.25, s*0.7)
    b_r = (s*0.75, s*0.7)
    bottom = (s*0.5, s*0.95)
    
    c1, c2, c3 = (s*0.5, s*0.4), (s*0.4, s*0.6), (s*0.6, s*0.6)
    
    d.polygon([top, t_r, c1, t_l], fill=c_light)
    d.polygon([t_l, c1, c2, b_l], fill=c_base)
    d.polygon([t_r, b_r, c3, c1], fill=c_dark)
    d.polygon([c2, b_l, bottom, b_r, c3], fill=c_base)
    d.polygon([c1, c2, c3], fill=c_light)
    
    outer = [top, t_r, b_r, bottom, b_l, t_l]
    d.polygon(outer, outline=c_rim, width=int(s/25))

def healer(d, s):
    # Emerald Diamond-Cross
    c_light = (110, 220, 150)
    c_base = (50, 160, 90)
    c_dark = (25, 90, 45)
    c_rim = (190, 255, 210)
    
    w = s * 0.22
    cx, cy = s/2, s/2
    
    o_top = (cx, s*0.1)
    o_bot = (cx, s*0.9)
    o_l = (s*0.1, cy)
    o_r = (s*0.9, cy)
    i_tl = (cx-w, cy-w)
    i_tr = (cx+w, cy-w)
    i_bl = (cx-w, cy+w)
    i_br = (cx+w, cy+w)
    
    c = (cx, cy)
    
    d.polygon([o_top, i_tr, c, i_tl], fill=c_light)
    d.polygon([o_l, i_tl, c, i_bl], fill=c_base)
    d.polygon([o_r, i_tr, c, i_br], fill=c_dark)
    d.polygon([o_bot, i_br, c, i_bl], fill=c_dark)

    outer = [o_top, i_tr, o_r, i_br, o_bot, i_bl, o_l, i_tl]
    d.polygon(outer, outline=c_rim, width=int(s/25))

def dps(d, s):
    # Ruby Sword/Dagger
    c_light = (240, 90, 90)
    c_base = (180, 30, 30)
    c_dark = (100, 10, 10)
    c_rim = (255, 190, 190)
    
    top = (s*0.5, s*0.05)
    t_l = (s*0.25, s*0.35)
    t_r = (s*0.75, s*0.35)
    bottom = (s*0.5, s*0.95)
    
    c1, c2, c3 = (s*0.5, s*0.3), (s*0.4, s*0.45), (s*0.6, s*0.45)
    c4 = (s*0.5, s*0.6)
    
    d.polygon([top, c1, t_l], fill=c_light)
    d.polygon([top, t_r, c1], fill=c_base)
    d.polygon([t_l, c1, c2], fill=c_base)
    d.polygon([t_r, c3, c1], fill=c_dark)
    d.polygon([c2, c1, c3, c4], fill=c_base)
    d.polygon([t_l, c2, c4, bottom], fill=c_dark)
    d.polygon([t_r, bottom, c4, c3], fill=c_dark)
    
    outer = [top, t_r, bottom, t_l]
    d.polygon(outer, outline=c_rim, width=int(s/25))

def leader(d, s):
    # Topaz Crown
    c_light = (255, 220, 90)
    c_base = (210, 160, 30)
    c_dark = (140, 90, 10)
    c_rim = (255, 240, 170)
    
    b_l = (s*0.15, s*0.85)
    b_r = (s*0.85, s*0.85)
    t_c = (s*0.5, s*0.15)
    t_l = (s*0.15, s*0.35)
    t_r = (s*0.85, s*0.35)
    i_l = (s*0.35, s*0.55)
    i_r = (s*0.65, s*0.55)
    center_b = (s*0.5, s*0.7)
    
    d.polygon([t_l, i_l, (s*0.3, s*0.7), b_l], fill=c_light)
    d.polygon([t_r, b_r, (s*0.7, s*0.7), i_r], fill=c_dark)
    d.polygon([t_c, center_b, i_l], fill=c_light)
    d.polygon([t_c, i_r, center_b], fill=c_dark)
    d.polygon([i_l, center_b, (s*0.3, s*0.7)], fill=c_base)
    d.polygon([i_r, (s*0.7, s*0.7), center_b], fill=c_base)
    d.polygon([b_l, (s*0.3, s*0.7), center_b, (s*0.7, s*0.7), b_r, (s*0.7, s*0.85), (s*0.3, s*0.85)], fill=c_base)
    
    outer = [t_l, i_l, t_c, i_r, t_r, b_r, b_l]
    d.polygon(outer, outline=c_rim, width=int(s/25))

def combat(d, s):
    c_light = (255, 90, 90)
    c_base = (190, 40, 40)
    c_dark = (120, 15, 15)
    c_rim = (255, 180, 180)
    
    w = s * 0.12
    # Blade 1 (Bottom Left to Top Right)
    b1_p = [(s*0.2, s*0.8), (s*0.8, s*0.2), (s*0.8+w, s*0.2+w), (s*0.2+w, s*0.8+w)]
    d.polygon([(s*0.2, s*0.8), (s*0.5+w/2, s*0.5+w/2), (s*0.2+w, s*0.8+w)], fill=c_dark)
    d.polygon([(s*0.2, s*0.8), (s*0.8, s*0.2), (s*0.8+w, s*0.2+w), (s*0.5+w/2, s*0.5+w/2)], fill=c_base)
    d.polygon(b1_p, outline=c_rim, width=int(s/25))
    
    # Blade 2 (Top Left to Bottom Right)
    b2_p = [(s*0.2, s*0.2), (s*0.8, s*0.8), (s*0.8-w, s*0.8+w), (s*0.2-w, s*0.2+w)]
    d.polygon([(s*0.2, s*0.2), (s*0.8, s*0.8), (s*0.5-w/2, s*0.5+w/2), (s*0.2-w, s*0.2+w)], fill=c_light)
    d.polygon([(s*0.5-w/2, s*0.5+w/2), (s*0.8, s*0.8), (s*0.8-w, s*0.8+w)], fill=c_dark)
    d.polygon(b2_p, outline=c_rim, width=int(s/25))

def rest(d, s):
    c_light = (160, 110, 240)
    c_base = (110, 60, 190)
    c_dark = (60, 25, 110)
    c_rim = (220, 180, 255)
    
    o1, o2, o3, o4, o5 = (s*0.35, s*0.1), (s*0.65, s*0.2), (s*0.85, s*0.5), (s*0.65, s*0.8), (s*0.35, s*0.9)
    i1, i2, i3, i4, i5 = (o1[0]+s*0.1, o1[1]+s*0.15), (s*0.55, s*0.35), (s*0.6, s*0.5), (s*0.55, s*0.65), (o5[0]+s*0.1, o5[1]-s*0.15)
    
    d.polygon([o1, o2, i2, i1], fill=c_light)
    d.polygon([o2, o3, i3, i2], fill=c_light)
    d.polygon([o3, o4, i4, i3], fill=c_base)
    d.polygon([o4, o5, i5, i4], fill=c_dark)
    
    outer = [o1, o2, o3, o4, o5, i5, i4, i3, i2, i1]
    d.polygon(outer, outline=c_rim, width=int(s/30))

path = r"C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI_UF\Media\Icons"
create_icon(64, tank, os.path.join(path, "tank_polygon.tga"))
create_icon(64, healer, os.path.join(path, "healer_polygon.tga"))
create_icon(64, dps, os.path.join(path, "dps_polygon.tga"))
create_icon(64, leader, os.path.join(path, "leader_polygon.tga"))
create_icon(128, combat, os.path.join(path, "combat_polygon.tga"))
create_icon(256, rest, os.path.join(path, "rest_polygon.tga"))

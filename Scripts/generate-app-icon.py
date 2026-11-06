"""Generate the code-drawn app icon using only Python's standard library."""
import math
from pathlib import Path
import struct
import zlib

SIZE = 1024
OUT = Path(__file__).resolve().parents[1] / 'Apps/EnglishTrainer/Assets.xcassets/AppIcon.appiconset/AppIcon.png'

def pill(x, y, x0, y0, x1, y1, radius):
    dx, dy = x1-x0, y1-y0
    t = max(0, min(1, ((x-x0)*dx+(y-y0)*dy)/(dx*dx+dy*dy)))
    return (x-x0-t*dx)**2+(y-y0-t*dy)**2 <= radius**2

def color(x, y):
    background = (12, int(37 + 17*y/SIZE), int(44 + 16*y/SIZE))
    radius = math.hypot(x-512, y-490)
    band = y <= 490 and 240 <= radius <= 298
    band |= pill(x,y,243,490,243,643,29) or pill(x,y,781,490,781,643,29)
    if band:
        return (221, 255, 246)
    for cx in (244, 780):
        if abs(x-cx) <= 73 and 470 <= y <= 667:
            return (35, 220, 193)
        if (x-cx)**2+(y-470)**2 <= 73**2 or (x-cx)**2+(y-667)**2 <= 73**2:
            return (35, 220, 193)
    for cx, top, bottom in ((420,475,580),(481,403,655),(542,452,607),(603,487,571)):
        if pill(x,y,cx,top,cx,bottom,17):
            return (35,220,193)
    if pill(x,y,360,773,512,818,15) or pill(x,y,512,818,664,773,15):
        return (221,255,246)
    return background

raw = bytearray()
for y in range(SIZE):
    raw.append(0)
    for x in range(SIZE):
        samples = [color(x+dx,y+dy) for dx,dy in ((.25,.25),(.75,.25),(.25,.75),(.75,.75))]
        raw.extend(round(sum(c[channel] for c in samples)/4) for channel in range(3))
def chunk(kind, data):
    return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!IIBBBBB',SIZE,SIZE,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
print('Generated opaque RGB 1024x1024 AppIcon.png')

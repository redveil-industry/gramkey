"""Builds Gramkey icon layers: knockouts done as real geometry so mono/clear modes keep the silhouette."""
import sys
from pathlib import Path
from shapely.geometry import box, LineString
from shapely.geometry.polygon import orient

out = Path(sys.argv[1])
DY = -12  # optical lift: visual centre slightly above geometric centre

def rrect(x, y, w, h, r):
    return box(x + r, y + r + DY, x + w - r, y + h - r + DY).buffer(r, quad_segs=32)

def path_d(geom):
    polys = getattr(geom, "geoms", [geom])
    d = []
    for p in polys:
        p = orient(p)
        for ring in [p.exterior, *p.interiors]:
            pts = list(ring.coords)
            d.append("M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z")
    return " ".join(d)

def svg(name, geom, fill):
    (out / name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
        f'  <path fill="{fill}" fill-rule="evenodd" d="{path_d(geom)}"/>\n</svg>\n')

front = rrect(232, 370, 440, 440, 108)
back = rrect(372, 214, 420, 420, 104).difference(front.buffer(28, quad_segs=32))
caret = LineString([(340, 654 + DY), (452, 530 + DY), (564, 654 + DY)]).buffer(36, quad_segs=32, cap_style="round", join_style="round")
svg("02-keycap-back.svg", back, "#FF9F0A")
svg("03-keycap-front.svg", front.difference(caret), "#F5F5F7")

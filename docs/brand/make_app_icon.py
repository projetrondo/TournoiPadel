# Génère l icône EAGLE (1024 px, sans transparence) : python3 make_app_icon.py AppIcon.png
import sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S = 2048  # suréchantillonnage, réduit à 1024
head = [(4,50),(18,32),(36,18),(56,11),(74,12),(87,19),(96,31),(100,45),(97,60),(91,52),(84,49),(79,57),(69,59),(63,71),(56,95),(45,85),(42,73),(30,83),(31,67),(15,73),(22,57)]
eye = [(58,29),(80,35),(63,39)]
mouth = [(79,44),(95,40),(95,42.5),(81,47)]

def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))

# Fond : carbone avec halo chaud au centre.
bg = Image.new("RGB", (S,S), (11,13,16))
glow = Image.new("L", (S,S), 0)
ImageDraw.Draw(glow).ellipse((S*0.12,S*0.10,S*0.88,S*0.86), fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(S*0.12))
warm = Image.new("RGB", (S,S), (70,50,18))
bg = Image.composite(warm, bg, glow.point(lambda v: int(v*0.75)))

def gold_gradient(w,h):
    g = Image.new("RGB",(w,h))
    px = g.load()
    stops = [(0,(255,226,154)),(0.5,(255,200,87)),(1,(184,134,43))]
    for y in range(h):
        for x in range(0,w):
            t = (x/w*0.45 + y/h*0.55)
            for i in range(len(stops)-1):
                if stops[i][0] <= t <= stops[i+1][0]:
                    u = (t-stops[i][0])/(stops[i+1][0]-stops[i][0]); c = lerp(stops[i][1],stops[i+1][1],u); break
            px[x,y]=c
    return g
small = gold_gradient(256,256)
gold = small.resize((S,S), Image.BICUBIC)

# Bordure dorée arrondie.
inset = int(S*0.055); radius = int(S*0.17); width = int(S*0.022)
border = Image.new("L",(S,S),0)
d = ImageDraw.Draw(border)
d.rounded_rectangle((inset,inset,S-inset,S-inset), radius=radius, fill=255)
d.rounded_rectangle((inset+width,inset+width,S-inset-width,S-inset-width), radius=radius-width, fill=0)
bglow = border.filter(ImageFilter.GaussianBlur(S*0.015))
bg = Image.composite(Image.new("RGB",(S,S),(255,200,87)), bg, bglow.point(lambda v:int(v*0.5)))
bg = Image.composite(gold, bg, border)

# Aigle.
scale = S*0.0062; ox = S*0.16; oy = S*0.17
def pts(p): return [(ox+x*scale, oy+y*scale) for x,y in p]
mask = Image.new("L",(S,S),0)
md = ImageDraw.Draw(mask)
md.polygon(pts(head), fill=255); md.polygon(pts(eye), fill=0); md.polygon(pts(mouth), fill=0)
eglow = mask.filter(ImageFilter.GaussianBlur(S*0.03))
bg = Image.composite(Image.new("RGB",(S,S),(255,200,87)), bg, eglow.point(lambda v:int(v*0.45)))
bg = Image.composite(gold, bg, mask)

# Balle de padel (jaune-vert, couture claire, petits trous) en bas à droite.
cx, cy, r = S*0.70, S*0.70, S*0.15
ball = Image.new("L",(S,S),0)
ImageDraw.Draw(ball).ellipse((cx-r,cy-r,cx+r,cy+r), fill=255)
shadow = ball.filter(ImageFilter.GaussianBlur(S*0.02))
bg = Image.composite(Image.new("RGB",(S,S),(0,0,0)), bg, shadow.point(lambda v:int(v*0.6)))
shade = Image.new("RGB",(S,S))
sp = shade.load()
for y in range(int(cy-r)-2, int(cy+r)+2):
    for x in range(int(cx-r)-2, int(cx+r)+2):
        dx, dy = (x-(cx-r*0.35))/r, (y-(cy-r*0.4))/r
        t = min(1, math.hypot(dx,dy)/1.6)
        sp[x,y] = lerp((236,255,90),(120,160,0),t)
bg = Image.composite(shade, bg, ball)
seam = Image.new("L",(S,S),0)
sd = ImageDraw.Draw(seam)
w = int(S*0.012)
sd.ellipse((cx-r*2.15, cy-r*0.95, cx-r*0.35, cy+r*0.95), outline=255, width=w)
sd.ellipse((cx+r*0.35, cy-r*0.95, cx+r*2.15, cy+r*0.95), outline=255, width=w)
seam = ImageChops.multiply(seam, ball)
bg = Image.composite(Image.new("RGB",(S,S),(248,252,235)), bg, seam)
# Reflet pour le volume.
hl = Image.new("L",(S,S),0)
ImageDraw.Draw(hl).ellipse((cx-r*0.62,cy-r*0.72,cx-r*0.18,cy-r*0.38), fill=255)
hl = hl.filter(ImageFilter.GaussianBlur(S*0.012))
bg = Image.composite(Image.new("RGB",(S,S),(255,255,255)), bg, hl.point(lambda v:int(v*0.45)))

out = bg.resize((1024,1024), Image.LANCZOS)
out.save(sys.argv[1])

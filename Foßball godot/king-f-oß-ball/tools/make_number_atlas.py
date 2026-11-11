"""Number atlas 1..99 (10x10 grid, cell 128px, cell index = number, row-major from top-left; cell 0 unused).
Run: python make_number_atlas.py out.png"""
import sys
from PIL import Image, ImageDraw, ImageFont
C, N = 128, 10
img = Image.new("RGBA", (C * N, C * N), (255, 255, 255, 0))
d = ImageDraw.Draw(img)
fp = next(p for p in ("/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf") if __import__("os").path.exists(p))
for n in range(1, 100):
    t = str(n)
    size = 120
    while True:
        f = ImageFont.truetype(fp, size)
        bb = d.textbbox((0, 0), t, font=f)
        if (bb[2] - bb[0]) <= C * 0.9 and (bb[3] - bb[1]) <= C * 0.8:
            break
        size -= 4
    x0, y0 = (n % N) * C, (n // N) * C
    d.text((x0 + (C - (bb[2] - bb[0])) / 2 - bb[0], y0 + (C - (bb[3] - bb[1])) / 2 - bb[1]), t, font=f, fill=(255, 255, 255, 255))
img.save(sys.argv[1])

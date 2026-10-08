"""Compone las capturas de la App Store (1320x2868, iPhone 6,9") con un título encima.
Parte de capturas crudas del simulador en store/capturas_iphone_6.9/_crudo_*.png (datos de ejemplo, sin datos reales).
Uso: python3 store/generar_capturas.py"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import glob, os

W, H = 1320, 2868
FUENTE = "/System/Library/Fonts/Avenir Next.ttc"
TITULOS = {
    "1_lista": ("Tu lista de la compra,", "ordenada por urgencia"),
    "2_tienda": ("Cada producto en el súper", "que más te conviene"),
    "3_menu": ("Escáner, ofertas, comparador", "y listas compartidas"),
    "4_ficha": ("Frío, cantidad y precio", "al detalle"),
    "5_oscuro": ("También en modo oscuro", ""),
}


def fondo():
    g = Image.new("RGB", (W, H)); px = g.load()
    for y in range(H):
        for x in range(W):
            t = (x / W) * 0.4 + (y / H) * 0.6
            px[x, y] = (int(14 + (3 - 14) * t), int(78 + (30 - 78) * t), int(150 + (62 - 150) * t))
    return g


for ruta in sorted(glob.glob("store/capturas_iphone_6.9/_crudo_*.png")):
    nombre = os.path.basename(ruta)[len("_crudo_"):-4]
    l1, l2 = TITULOS[nombre]
    base = fondo().convert("RGBA")
    d = ImageDraw.Draw(base)
    f = ImageFont.truetype(FUENTE, 78, index=1)
    for i, linea in enumerate((l1, l2)):
        if not linea: continue
        w = d.textlength(linea, font=f)
        d.text(((W - w) / 2, 150 + i * 105), linea, font=f, fill="white")
    k = 0.87
    cap = Image.open(ruta).convert("RGB").resize((int(W * k), int(H * k)), Image.LANCZOS)
    m = Image.new("L", cap.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, cap.width - 1, cap.height + 200), radius=90, fill=255)
    x0, y0 = (W - cap.width) // 2, 420
    sombra = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(sombra).rounded_rectangle((x0, y0 + 20, x0 + cap.width, y0 + cap.height + 220), radius=90, fill=(0, 0, 0, 120))
    base = Image.alpha_composite(base, sombra.filter(ImageFilter.GaussianBlur(30)))
    base.paste(cap, (x0, y0), m)
    out = f"store/capturas_iphone_6.9/{nombre}.png"
    base.convert("RGB").save(out, "PNG", optimize=True)
    print(out)

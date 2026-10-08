"""Genera las imágenes de la ficha de la App Store (cabecera 21:9 y resultados de búsqueda 3:2).
Sin canal alfa, como exige Apple. Uso: python3 store/generar_imagenes.py"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FUENTE = "/System/Library/Fonts/Avenir Next.ttc"
ICONO = "assets/icon_1024.png"


def fuente(tam, negrita=True):
    return ImageFont.truetype(FUENTE, tam, index=1 if negrita else 7)  # 1 = Bold, 7 = Medium


def fondo(w, h):
    g = Image.new("RGB", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x / w) * 0.55 + (y / h) * 0.45
            px[x, y] = (int(14 + (3 - 14) * t), int(78 + (30 - 78) * t), int(150 + (62 - 150) * t))
    return g


def icono(lado):
    im = Image.open(ICONO).convert("RGB").resize((lado, lado), Image.LANCZOS)
    m = Image.new("L", (lado, lado), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, lado - 1, lado - 1), radius=int(lado * 0.225), fill=255)
    sombra = Image.new("RGBA", (lado + 160, lado + 160), (0, 0, 0, 0))
    ImageDraw.Draw(sombra).rounded_rectangle((80, 100, 80 + lado, 100 + lado), radius=int(lado * 0.225), fill=(0, 0, 0, 110))
    return im, m, sombra.filter(ImageFilter.GaussianBlur(40))


def componer(w, h, lado_icono, x_texto, y_texto, tam_titulo, tam_sub, tam_chip, nombre):
    base = fondo(w, h).convert("RGBA")
    ic, mask, sombra = icono(lado_icono)
    cx, cy = w - lado_icono - int(w * 0.07), (h - lado_icono) // 2
    base.alpha_composite(sombra, (cx - 80, cy - 80))
    base.paste(ic, (cx, cy), mask)
    # el bloque de texto (título, subtítulo y etiquetas) se centra en vertical
    bloque = int(tam_titulo * 1.25) + int(tam_sub * 2.9) + tam_chip * 2
    y_texto = (h - bloque) // 2
    d = ImageDraw.Draw(base)
    d.text((x_texto, y_texto), "MultiMarket", font=fuente(tam_titulo), fill="white")
    d.text((x_texto, y_texto + int(tam_titulo * 1.25)), "Tu lista de la compra,", font=fuente(tam_sub, False), fill=(214, 231, 255))
    d.text((x_texto, y_texto + int(tam_titulo * 1.25) + int(tam_sub * 1.25)), "en el súper que más te conviene", font=fuente(tam_sub, False), fill=(214, 231, 255))
    y = y_texto + int(tam_titulo * 1.25) + int(tam_sub * 2.9)
    x = x_texto
    f = fuente(tam_chip)
    capa = Image.new("RGBA", base.size, (0, 0, 0, 0))
    dc = ImageDraw.Draw(capa)
    for texto in ("Precio", "Cercanía", "Frío", "Compartida"):
        tw = d.textlength(texto, font=f)
        pad = int(tam_chip * 0.55)
        dc.rounded_rectangle((x, y, x + tw + 2 * pad, y + tam_chip * 2), radius=tam_chip, fill=(255, 255, 255, 40), outline=(255, 255, 255, 230), width=3)
        dc.text((x + pad, y + tam_chip * 0.42), texto, font=f, fill=(255, 255, 255, 255))
        x += tw + 2 * pad + int(tam_chip * 0.6)
    base = Image.alpha_composite(base, capa)
    base.convert("RGB").save(nombre, "PNG", optimize=True)
    print(nombre, w, h)


componer(3840, 1646, 1180, 260, 330, 250, 100, 62, "store/cabecera_3840x1646.png")
componer(3840, 2560, 1500, 260, 640, 270, 108, 66, "store/busqueda_3840x2560.png")

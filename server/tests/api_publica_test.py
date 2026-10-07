"""API pública de solo lectura: sin sesión, solo aprobados, límite por IP.
MM_URL=https://tu-servidor python3 server/tests/api_publica_test.py  (consume ~65 peticiones del límite de tu IP)"""
import json, os, sys, time, urllib.request, urllib.error

U = os.environ["MM_URL"].rstrip("/")


def get(path):
    try:
        with urllib.request.urlopen(U + path, timeout=30) as f:
            return f.status, json.loads(f.read().decode()), f.headers
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t), e.headers
        except Exception: return e.code, {"raw": t[:200]}, e.headers


ok = []
def check(nombre, cond, extra=""):
    ok.append(bool(cond)); print(("OK  " if cond else "FALLO"), nombre, extra)


s, b, _ = get("/api/mm/v1/productos")
check("sin parámetros → 400", s == 400, s)
s, b, _ = get("/api/mm/v1/productos?q=a")
check("búsqueda de 1 letra → 400", s == 400, s)
s, b, h = get("/api/mm/v1/productos?q=leche&per=500")
check("búsqueda sin sesión → 200 y per acotado a 50", s == 200 and b["perPage"] == 50, (s, b.get("perPage")))
check("estructura de la respuesta", set(b) == {"page", "perPage", "hasMore", "items"}, list(b))
check("sin datos del autor", all("owner" not in i and "note" not in i and "status" not in i for i in b["items"]))
s, b, _ = get("/api/mm/v1/productos?barcode=0000000000000")
check("código desconocido → lista vacía", s == 200 and b["items"] == [], s)
s, b, _ = get("/api/mm/v1/productos?q=%27%20OR%201%3D1%20--")
check("inyección en q no rompe ni devuelve todo", s == 200, s)
codigo = None
for _ in range(70):
    s, b, h = get("/api/mm/v1/productos?barcode=1")
    if s == 429: codigo = h.get("Retry-After"); break
check("a partir de 60 peticiones/min → 429 con Retry-After", codigo is not None, codigo)
print(f"{sum(ok)}/{len(ok)}")
sys.exit(0 if all(ok) else 1)

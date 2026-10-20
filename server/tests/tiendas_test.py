"""Caché de supermercados: valida parámetros, devuelve datos de OpenStreetMap con atribución y respeta el límite.
MM_URL=https://tu-servidor python3 server/tests/tiendas_test.py  (consume ~35 peticiones del límite de tu IP)"""
import json, os, sys, urllib.request, urllib.error

U = os.environ["MM_URL"].rstrip("/")


def get(path):
    try:
        with urllib.request.urlopen(U + path, timeout=60) as f:
            return f.status, json.loads(f.read().decode()), f.headers
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t), e.headers
        except Exception: return e.code, {"raw": t[:200]}, e.headers


ok = []
def check(n, c, extra=""):
    print(("OK   " if c else "FAIL ") + n, extra if not c else ""); ok.append(bool(c))


s, d, _ = get("/api/mm/v1/tiendas")
check("sin coordenadas → 400", s == 400, s)
s, d, _ = get("/api/mm/v1/tiendas?lat=10&lon=0&r=3")
check("fuera de España → 400", s == 400, s)
for _ in range(3):  # la primera consulta de una zona puede devolver «incompleto» mientras se descargan celdas
    s, d, _ = get("/api/mm/v1/tiendas?lat=40.42&lon=-3.70&r=3")
    if s == 200 and not d.get("incompleto"): break
check("Madrid: respuesta 200 y completa", s == 200 and not d.get("incompleto"), d if s != 200 else d.get("incompleto"))
check("hay supermercados con coordenadas", s == 200 and len(d["items"]) > 20 and all("lat" in x and "lon" in x for x in d["items"]))
check("atribución de OpenStreetMap en la respuesta", "OpenStreetMap" in d.get("atribucion", ""), d.get("atribucion"))
check("solo datos de OSM (sin campos de usuarios)", all(set(x) <= {"t", "id", "lat", "lon", "name", "brand", "operator", "opening_hours"} for x in d["items"]))
s, d2, _ = get("/api/mm/v1/tiendas?lat=40.42&lon=-3.70&r=3")
check("segunda consulta idéntica (desde la caché)", s == 200 and len(d2["items"]) == len(d["items"]))
limite = None
for _ in range(40):
    s, _, h = get("/api/mm/v1/tiendas?lat=40.42&lon=-3.70&r=1")
    if s == 429: limite = h.get("Retry-After"); break
check("a partir de 30/min → 429 con Retry-After", limite is not None, limite)
print(f"{sum(ok)}/{len(ok)}")
sys.exit(0 if all(ok) else 1)

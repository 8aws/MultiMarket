"""Precios de la comunidad: se envían con sesión, se agregan por mediana, sin autor, con atípicos y límite.
MM_URL=https://tu-servidor python3 server/tests/precios_test.py  (≤ 1 vez/minuto)"""
import json, os, sys, time, urllib.request, urllib.error, uuid, datetime

U = os.environ["MM_URL"].rstrip("/")


def call(path, method="GET", token=None, body=None):
    h = {"Content-Type": "application/json"}
    if token: h["Authorization"] = token
    r = urllib.request.Request(U + path, method=method, headers=h, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            t = f.read().decode(); return f.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"raw": t[:200]}


def mkuser():
    em = f"{uuid.uuid4().hex[:10]}@device.invalid"; pw = uuid.uuid4().hex
    s, r = call("/api/collections/users/records", "POST", None, {"email": em, "password": pw, "passwordConfirm": pw})
    assert s == 200, (s, r); time.sleep(1.6)
    s, a = call("/api/collections/users/auth-with-password", "POST", None, {"identity": em, "password": pw})
    assert s == 200, (s, a); time.sleep(1.6)
    return a["record"]["id"], a["token"]


ok = []
def check(n, c, extra=""):
    print(("OK   " if c else "FAIL ") + n, extra if not c else ""); ok.append(bool(c))


hoy = datetime.date.today()
dias = [(hoy - datetime.timedelta(days=i)).isoformat() for i in range(5)]
clave = "test-" + uuid.uuid4().hex[:8]
ua, ta = mkuser(); ub, tb = mkuser(); uc, tc = mkuser()
try:
    obs = lambda p, d: {"key": clave, "base": "base-" + clave, "chain": "lidl", "price": p, "name": "Producto de prueba", "fecha": d}
    s, r = call("/api/mm/v1/precios", "POST", None, {"items": [obs(1.0, dias[0])]})
    check("sin sesión no se envían precios", s in (401, 403), s)
    s, r = call("/api/mm/v1/precios", "POST", ta, {"items": [obs(1.00, dias[0]), obs(1.00, dias[0]), obs(-3, dias[0]), obs(1.2, "mañana")]})
    check("se guarda lo válido y se omite lo demás (duplicado, negativo, fecha)", s == 200 and r["guardados"] == 1 and r["omitidos"] == 3, (s, r))
    s, _ = call("/api/mm/v1/precios", "POST", tb, {"items": [obs(1.10, dias[1])]})
    s, _ = call("/api/mm/v1/precios", "POST", tc, {"items": [obs(1.20, dias[2])]})
    s, r = call("/api/mm/v1/precios?keys=" + clave, "GET")
    it = (r.get("items") or [{}])[0]
    check("lectura pública agregada: mediana de 3 observaciones", s == 200 and it.get("price") == 1.10 and it.get("n") == 3, r)
    check("sin autor en la respuesta", all("owner" not in x for x in r.get("items", [])), r)
    s, r = call("/api/mm/v1/precios?bases=base-" + clave, "GET")
    check("también por clave «por nombre»", s == 200 and len(r.get("items", [])) == 1, r)
    s, _ = call("/api/mm/v1/precios", "POST", ta, {"items": [obs(40.0, dias[3])]})
    s, r = call("/api/mm/v1/precios?keys=" + clave, "GET")
    check("un valor atípico no mueve la mediana", s == 200 and r["items"][0]["price"] == 1.10 and r["items"][0]["n"] == 3, r)
    s, _ = call("/api/collections/precios/records", "GET", ta)
    check("la colección en bruto no es accesible", s in (400, 403, 404), s)
    s, r = call("/api/mm/v1/precios", "GET")
    check("lectura sin claves → 400", s == 400, s)
finally:
    for uid, tok in ((ua, ta), (ub, tb), (uc, tc)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

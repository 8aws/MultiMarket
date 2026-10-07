"""Productos nuevos de la comunidad: propuesta, moderación y visibilidad. Sin credenciales de admin.
MM_URL=https://tu-servidor python3 server/tests/productos_test.py  (≤ 1 vez/minuto)"""
import json, os, sys, time, urllib.request, urllib.error, uuid

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


ua, ta = mkuser(); ub, tb = mkuser()
key = "test-" + uuid.uuid4().hex[:8]
try:
    s, r = call("/api/collections/productos/records", "POST", ta, {"key": key.upper(), "name": "Yogur de prueba", "brand": "Marca", "quantity": "4 x 125 g", "cold": True, "generic_key": "yogur-prueba|500g"})
    check("proponer producto", s == 200, (s, r)); pid = r.get("id")
    check("entra pendiente y a nombre del autor", r.get("status") == "pending" and r.get("owner") == ua, r)
    check("la clave se normaliza", r.get("key") == key, r)
    s, _ = call("/api/collections/productos/records", "POST", tb, {"key": key, "name": "Duplicado"})
    check("no admite duplicados", s == 400, s)
    s, l = call(f"/api/collections/productos/records?filter=key='{key}'", "GET", None)
    check("el público no ve pendientes", s == 200 and l.get("items") == [], l)
    s, l = call(f"/api/collections/productos/records?filter=key='{key}'", "GET", tb)
    check("otro usuario no ve pendientes", s == 200 and l.get("items") == [], l)
    s, l = call(f"/api/collections/productos/records?filter=key='{key}'", "GET", ta)
    check("el autor ve el suyo", s == 200 and len(l.get("items", [])) == 1, l)
    s, _ = call("/api/collections/productos/records", "POST", ta, {"key": key + "x", "name": "x", "status": "approved"})
    check("no se puede auto-aprobar", s in (400, 403), s)
    s, _ = call("/api/collections/productos/records", "POST", None, {"key": key + "y", "name": "y"})
    check("sin sesión no se propone", s in (400, 403), s)
    s, _ = call(f"/api/collections/productos/records/{pid}", "PATCH", ta, {"status": "approved"})
    check("el autor no puede aprobar", s in (400, 403, 404), s)
    s, _ = call(f"/api/collections/productos/records/{pid}", "DELETE", tb)
    check("otro no lo borra", s in (403, 404), s)
    s, _ = call(f"/api/collections/productos/records/{pid}", "DELETE", ta)
    check("el autor lo retira", s == 204, s)
    s, _ = call("/api/collections/mm_estado/records", "GET", ta)
    check("mm_estado solo superusuario", s in (400, 403), s)
finally:
    for uid, tok in ((ua, ta), (ub, tb)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

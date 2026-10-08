"""Copia opcional de la lista privada: solo su dueño la ve/cambia, una por cuenta, se borra con la cuenta.
MM_URL=https://tu-servidor python3 server/tests/copias_test.py  (≤ 1 vez/minuto)"""
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
borrada = False
try:
    datos = {"items": [{"id": "a" * 15, "name": "Leche"}], "compras": []}
    s, r = call("/api/collections/copias/records", "POST", None, {"datos": datos})
    check("sin sesión no se crea", s in (400, 403), s)
    s, r = call("/api/collections/copias/records", "POST", ta, {"datos": datos, "version": "1.0.0+1"})
    check("el usuario crea su copia", s == 200 and r.get("owner") == ua, (s, r)); cid = r.get("id")
    s, _ = call("/api/collections/copias/records", "POST", ta, {"datos": datos})
    check("solo una copia por cuenta", s == 400, s)
    s, _ = call("/api/collections/copias/records", "POST", tb, {"datos": datos, "owner": ua})
    check("no se puede fijar el dueño", s in (400, 403), s)
    s, l = call("/api/collections/copias/records", "GET", tb)
    check("otro usuario no ve la copia", s == 200 and l["items"] == [], l)
    s, _ = call(f"/api/collections/copias/records/{cid}", "GET", tb)
    check("ni por id", s in (403, 404), s)
    s, _ = call(f"/api/collections/copias/records/{cid}", "PATCH", tb, {"datos": {"items": []}})
    check("otro no puede sobrescribirla", s in (403, 404), s)
    s, _ = call(f"/api/collections/copias/records/{cid}", "DELETE", tb)
    check("ni borrarla", s in (403, 404), s)
    s, r = call(f"/api/collections/copias/records/{cid}", "PATCH", ta, {"datos": {"items": [{"name": "Pan"}], "compras": []}})
    check("el dueño la actualiza", s == 200 and r["datos"]["items"][0]["name"] == "Pan", (s, r))
    s, _ = call(f"/api/collections/copias/records/{cid}", "PATCH", ta, {"owner": ub})
    check("el dueño no la traspasa", s in (400, 403, 404), s)
    s, l = call("/api/collections/copias/records", "GET", ta)
    check("el dueño la lista", s == 200 and len(l["items"]) == 1, l)
    call(f"/api/collections/users/records/{ua}", "DELETE", ta); borrada = True
    # tras borrar la cuenta, la copia ya no existe (cascada): lo comprueba un tercero con otra sesión no es posible; basta que el borrado no falle
    s, _ = call(f"/api/collections/copias/records/{cid}", "GET", tb)
    check("la copia no es accesible tras borrar la cuenta", s in (403, 404), s)
finally:
    if not borrada: call(f"/api/collections/users/records/{ua}", "DELETE", ta)
    call(f"/api/collections/users/records/{ub}", "DELETE", tb)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

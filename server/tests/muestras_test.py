"""Muestras de tickets: sin sesión no entra nada, un usuario NO autorizado recibe 403 y nadie las lee salvo el administrador.
(La parte de usuario autorizado necesita al administrador: se prueba en local con Docker.)
MM_URL=https://tu-servidor python3 server/tests/muestras_test.py  (≤ 1 vez/minuto)"""
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


ua, ta = mkuser()
try:
    m = {"version": "1.1.0+13", "fuente": "pdf", "lineas": [["LECHE 1,05"]], "resultado": {"total": 1.05}}
    s, r = call("/api/collections/muestras/records", "POST", None, m)
    check("sin sesión no se aceptan muestras", s in (400, 403), s)
    s, r = call("/api/collections/muestras/records", "POST", ta, m)
    check("un usuario no autorizado recibe 403", s == 403, (s, r))
    s, r = call("/api/collections/muestras/records", "GET", ta)
    check("nadie lista las muestras (solo el administrador)", s in (400, 403) or r.get("totalItems", 0) == 0, (s, r))
finally:
    call(f"/api/collections/users/records/{ua}", "DELETE", ta)
sys.exit(0 if all(ok) else 1)

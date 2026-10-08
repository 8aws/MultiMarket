"""Informes de errores: solo con sesión, el autor lo fija el servidor, nadie los lee salvo el administrador, límite por hora.
MM_URL=https://tu-servidor python3 server/tests/errores_test.py  (≤ 1 vez/minuto)"""
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
try:
    inf = {"version": "1.0.0+1", "sistema": "iOS 27", "mensaje": "Bad state: prueba", "traza": "#0 main (a.dart:1)"}
    s, r = call("/api/collections/errores/records", "POST", None, inf)
    check("sin sesión no se envían informes", s in (400, 403), s)
    s, r = call("/api/collections/errores/records", "POST", ta, inf)
    check("con sesión se crea", s == 200, (s, r))
    s, _ = call("/api/collections/errores/records", "POST", ta, {**inf, "owner": ub})
    check("no se puede fijar el autor", s in (400, 403), s)
    s, _ = call("/api/collections/errores/records", "POST", ta, {**inf, "mensaje": ""})
    check("el mensaje es obligatorio", s == 400, s)
    s, l = call("/api/collections/errores/records", "GET", ta)
    check("ni el autor puede listar informes", s in (400, 403), s)
    if r.get("id"):
        s, _ = call(f"/api/collections/errores/records/{r['id']}", "GET", ta)
        check("ni verlos uno a uno", s in (400, 403, 404), s)
        s, _ = call(f"/api/collections/errores/records/{r['id']}", "DELETE", ta)
        check("ni borrarlos", s in (400, 403, 404), s)
    cod = []
    for i in range(22):
        s, _ = call("/api/collections/errores/records", "POST", tb, inf); cod.append(s)
    check("límite de 20 por hora", 429 in cod and cod.count(200) <= 20, cod)
finally:
    for uid, tok in ((ua, ta), (ub, tb)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)  # sus informes se borran en cascada
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

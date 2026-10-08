"""Sanciones: un usuario no puede tocar sus propios campos de sanción ni usar las rutas de administración,
y sin sanción sigue pudiendo aportar. (La aplicación de la sanción exige ser superusuario: se prueba a mano desde moderación.)
MM_URL=https://tu-servidor python3 server/tests/sanciones_test.py  (≤ 1 vez/minuto)"""
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
    return a["record"], a["token"]


ok = []
def check(n, c, extra=""):
    print(("OK   " if c else "FAIL ") + n, extra if not c else ""); ok.append(bool(c))


u, t = mkuser(); uid = u["id"]
try:
    check("el usuario nuevo llega sin sanciones", not u.get("sancion_indef") and not u.get("sancion_hasta") and not u.get("sanciones_n"), u)
    for campo, valor in (("sancion_indef", False), ("sanciones_n", 0), ("sancion_hasta", "2999-01-01 00:00:00.000Z")):
        s, _ = call(f"/api/collections/users/records/{uid}", "PATCH", t, {campo: valor})
        check(f"no puede escribir {campo}", s in (400, 403, 404), s)  # PocketBase responde 404 cuando la regla de edición no se cumple
    s, r = call(f"/api/collections/users/records/{uid}", "GET", t)
    check("y sus campos de sanción siguen intactos", s == 200 and not r.get("sancion_indef") and not r.get("sanciones_n") and not r.get("sancion_hasta"), r)
    s, _ = call(f"/api/collections/users/records/{uid}", "PATCH", t, {"alias": "Nuevo"})
    check("sí puede cambiar su alias", s == 200, s)
    s, _ = call("/api/mm/sancionar", "POST", t, {"user": uid, "motivo": "x"})
    check("un usuario no puede sancionar", s in (401, 403), s)
    s, _ = call("/api/mm/sancion/levantar", "POST", t, {"user": uid})
    check("un usuario no puede levantar sanciones", s in (401, 403), s)
    s, _ = call("/api/mm/sancionar", "POST", None, {"user": uid})
    check("sin sesión tampoco", s in (401, 403), s)
    s, p = call("/api/collections/productos/records", "POST", t, {"key": "sancion-test-" + uuid.uuid4().hex[:6], "name": "Producto de prueba", "cold": False})
    check("sin sanción puede proponer productos", s == 200, (s, p))
    if s == 200: call(f"/api/collections/productos/records/{p['id']}", "DELETE", t)
    s, l = call("/api/collections/sanciones/records", "GET", t)
    check("el registro de sanciones no es visible", s in (400, 403, 404), s)
finally:
    call(f"/api/collections/users/records/{uid}", "DELETE", t)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

"""Borrado de cuenta: listas traspasadas o borradas, pendientes eliminados. Sin credenciales de admin.
MM_URL=https://tu-servidor python3 server/tests/cuenta_test.py  (≤ 1 vez/minuto)"""
import base64, json, os, sys, time, urllib.request, urllib.error, uuid

U = os.environ["MM_URL"].rstrip("/")
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")


def call(path, method="GET", token=None, body=None, raw=None, ctype=None):
    h = {}
    if token: h["Authorization"] = token
    data = raw
    if body is not None: data = json.dumps(body).encode(); h["Content-Type"] = "application/json"
    elif ctype: h["Content-Type"] = ctype
    r = urllib.request.Request(U + path, method=method, headers=h, data=data)
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
limpiar = []
try:
    s, h = call("/api/collections/hogares/records", "POST", ta, {"name": "Casa", "owner": ua})
    hid = h["id"]; limpiar.append(hid)
    call("/api/mm/join", "POST", tb, body={"code": h["invite_code"], "alias": "B"})
    b = "----mm" + uuid.uuid4().hex
    cuerpo = (f'--{b}\r\nContent-Disposition: form-data; name="key"\r\n\r\nclave-prueba\r\n--{b}\r\nContent-Disposition: form-data; name="consent"\r\n\r\ntrue\r\n'
              f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="f.png"\r\nContent-Type: image/png\r\n\r\n').encode() + PNG + f"\r\n--{b}--\r\n".encode()
    s, f = call("/api/collections/fotos/records", "POST", ta, raw=cuerpo, ctype=f"multipart/form-data; boundary={b}")
    check("foto pendiente creada", s == 200, (s, f)); fid = f.get("id")
    s, p = call("/api/collections/productos/records", "POST", ta, {"key": "prueba-cuenta-" + uuid.uuid4().hex[:6], "name": "Prueba cuenta"})
    check("producto pendiente creado", s == 200, (s, p)); pid = p.get("id")

    s, _ = call(f"/api/collections/users/records/{ua}", "DELETE", ta)
    check("el creador puede borrar su cuenta", s == 204, s)
    s, hh = call(f"/api/collections/hogares/records/{hid}", "GET", tb)
    check("la lista sigue existiendo para el otro miembro", s == 200, (s, hh))
    check("la lista pasa al siguiente miembro", hh.get("owner") == ub, hh)
    s, m = call(f"/api/collections/miembros/records?filter=hogar='{hid}'", "GET", tb)
    check("el miembro restante es ahora owner", s == 200 and [x["rol"] for x in m["items"]] == ["owner"], m)
    s, l = call(f"/api/collections/fotos/records/{fid}", "GET", tb)
    check("su foto pendiente se elimina", s in (403, 404), s)
    s, l = call(f"/api/collections/productos/records/{pid}", "GET", tb)
    check("su producto pendiente se elimina", s in (403, 404), s)

    s, _ = call(f"/api/collections/users/records/{ub}", "DELETE", tb)
    check("el último miembro puede borrar su cuenta", s == 204, s)
    limpiar.clear()
    ub = None
finally:
    for uid, tok in ((ua, ta), (ub, tb)):
        if uid: call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

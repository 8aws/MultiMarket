"""Reportes de fotos: crear, duplicados, visibilidad y que no se puedan manipular. Sin credenciales de admin.
MM_URL=https://tu-servidor python3 server/tests/reportes_test.py  (≤ 1 vez/minuto)"""
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
try:
    b = "----mm" + uuid.uuid4().hex
    cuerpo = (f'--{b}\r\nContent-Disposition: form-data; name="key"\r\n\r\nclave-rep\r\n--{b}\r\nContent-Disposition: form-data; name="consent"\r\n\r\ntrue\r\n'
              f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="f.png"\r\nContent-Type: image/png\r\n\r\n').encode() + PNG + f"\r\n--{b}--\r\n".encode()
    s, f = call("/api/collections/fotos/records", "POST", ta, raw=cuerpo, ctype=f"multipart/form-data; boundary={b}")
    fid = f["id"]
    s, r = call("/api/collections/reportes/records", "POST", tb, body={"foto": fid, "motivo": "producto-equivocado", "nota": "es otra marca"})
    check("crear reporte", s == 200, (s, r)); rid = r.get("id")
    check("entra abierto y a nombre del autor", r.get("status") == "open" and r.get("owner") == ub, r)
    s, _ = call("/api/collections/reportes/records", "POST", tb, body={"foto": fid, "motivo": "otro"})
    check("un usuario no reporta dos veces la misma foto", s == 400, s)
    s, _ = call("/api/collections/reportes/records", "POST", None, body={"foto": fid, "motivo": "otro"})
    check("sin sesión no se reporta", s in (400, 403), s)
    s, _ = call("/api/collections/reportes/records", "POST", ta, body={"foto": fid, "motivo": "inventado"})
    check("motivo no válido", s == 400, s)
    s, _ = call("/api/collections/reportes/records", "POST", ta, body={"foto": fid, "motivo": "otro", "status": "resolved"})
    check("no se puede fijar el estado", s in (400, 403), s)
    s, l = call("/api/collections/reportes/records", "GET", ta)
    check("un usuario no ve reportes ajenos", s == 200 and l["items"] == [], l)
    s, l = call("/api/collections/reportes/records", "GET", tb)
    check("el autor ve el suyo", s == 200 and len(l["items"]) == 1, l)
    s, _ = call(f"/api/collections/reportes/records/{rid}", "PATCH", tb, body={"status": "dismissed"})
    check("el autor no puede cerrar su reporte", s in (400, 403, 404), s)
    s, _ = call(f"/api/collections/reportes/records/{rid}", "DELETE", tb)
    check("no se borran reportes desde la app", s in (400, 403, 404), s)
    call(f"/api/collections/fotos/records/{fid}", "DELETE", ta)  # retira la foto de prueba (y su reporte en cascada)
finally:
    for uid, tok in ((ua, ta), (ub, tb)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

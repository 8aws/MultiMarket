"""Fotos de la comunidad: subida, moderación y visibilidad. Sin credenciales de admin.
MM_URL=https://tu-servidor python3 server/tests/fotos_test.py  (≤ 1 vez/minuto: alta de usuarios 5/min)"""
import base64, json, os, sys, time, urllib.request, urllib.error, uuid

U = os.environ["MM_URL"].rstrip("/")
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")


def call(path, method="GET", token=None, body=None, raw=None, ctype="application/json"):
    h = {}
    if token: h["Authorization"] = token
    data = raw
    if body is not None:
        data = json.dumps(body).encode(); h["Content-Type"] = "application/json"
    elif raw is not None:
        h["Content-Type"] = ctype
    r = urllib.request.Request(U + path, method=method, headers=h, data=data)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            t = f.read().decode(); return f.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"raw": t[:200]}


def multipart(fields, fname, content, mime):
    b = "----mm" + uuid.uuid4().hex
    out = b""
    for k, v in fields.items():
        out += f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    out += f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="{fname}"\r\nContent-Type: {mime}\r\n\r\n'.encode() + content + b"\r\n"
    out += f"--{b}--\r\n".encode()
    return out, f"multipart/form-data; boundary={b}"


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
ids = []
try:
    body, ct = multipart({"key": "8480000106483", "barcode": "8480000106483", "name": "Leche entera", "consent": "true"}, "f.png", PNG, "image/png")
    s, r = call("/api/collections/fotos/records", "POST", ta, raw=body, ctype=ct)
    check("subir foto con consentimiento", s == 200, (s, r)); fid = r.get("id"); ids.append(fid)
    check("entra como pendiente", r.get("status") == "pending", r)
    check("el servidor fija el autor", r.get("owner") == ua, r)
    s, l = call(f"/api/collections/fotos/records?filter=key='8480000106483'", "GET", None)
    check("público no ve las pendientes", s == 200 and l.get("items") == [], l)
    s, l = call(f"/api/collections/fotos/records?filter=key='8480000106483'", "GET", tb)
    check("otro usuario no ve las pendientes", s == 200 and l.get("items") == [], l)
    s, l = call(f"/api/collections/fotos/records?filter=key='8480000106483'", "GET", ta)
    check("el autor ve la suya", s == 200 and len(l.get("items", [])) == 1, l)
    body, ct = multipart({"key": "x", "consent": "false"}, "f.png", PNG, "image/png")
    s, _ = call("/api/collections/fotos/records", "POST", ta, raw=body, ctype=ct)
    check("sin consentimiento se rechaza", s in (400, 403), s)
    body, ct = multipart({"key": "x", "consent": "true", "status": "approved"}, "f.png", PNG, "image/png")
    s, _ = call("/api/collections/fotos/records", "POST", ta, raw=body, ctype=ct)
    check("no se puede auto-aprobar", s in (400, 403), s)
    body, ct = multipart({"key": "x", "consent": "true"}, "f.txt", b"no soy una imagen", "text/plain")
    s, _ = call("/api/collections/fotos/records", "POST", ta, raw=body, ctype=ct)
    check("solo imágenes", s == 400, s)
    body, ct = multipart({"key": "x", "consent": "true"}, "f.png", PNG, "image/png")
    s, _ = call("/api/collections/fotos/records", "POST", None, raw=body, ctype=ct)
    check("sin sesión no se sube", s in (400, 403), s)
    s, _ = call(f"/api/collections/fotos/records/{fid}", "PATCH", ta, {"status": "approved"})
    check("el autor no puede aprobar su foto", s in (400, 403, 404), s)
    s, _ = call(f"/api/collections/fotos/records/{fid}", "DELETE", tb)
    check("otro usuario no la borra", s in (403, 404), s)
    s, _ = call(f"/api/collections/fotos/records/{fid}", "DELETE", ta)
    check("el autor puede retirarla", s == 204, s)
finally:
    for uid, tok in ((ua, ta), (ub, tb)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

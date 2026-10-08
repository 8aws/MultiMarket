"""Avisos entre miembros («voy yo»): solo los miembros los crean y ven; no se suplanta ni se hace spam.
MM_URL=https://tu-servidor python3 server/tests/avisos_test.py  (≤ 1 vez/minuto: crea 3 usuarios)"""
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


ua, ta = mkuser(); ub, tb = mkuser(); uc, tc = mkuser()
hid = None
try:
    s, h = call("/api/collections/hogares/records", "POST", ta, {"name": "Casa", "emoji": "🏠", "owner": ua})
    hid = h["id"]; code = h["invite_code"]
    s, _ = call("/api/mm/join", "POST", tb, {"code": code, "alias": "Beto"})
    check("B se une a la lista", s == 200, s)
    aviso = {"hogar": hid, "user": ua, "alias": "Ana", "tipo": "voy", "texto": "Ana va a comprar en Lidl"}
    s, r = call("/api/collections/avisos/records", "POST", ta, aviso)
    check("un miembro crea un aviso", s == 200, (s, r)); rid = r.get("id")
    s, l = call(f"/api/collections/avisos/records?filter=hogar='{hid}'", "GET", tb)
    check("otro miembro lo ve", s == 200 and len(l["items"]) == 1, l)
    s, l = call("/api/collections/avisos/records", "GET", tc)
    check("quien no es miembro no ve nada", s == 200 and l["items"] == [], l)
    s, _ = call("/api/collections/avisos/records", "POST", tc, {**aviso, "user": uc})
    check("un ajeno no crea avisos en la lista", s in (400, 403), s)
    s, _ = call("/api/collections/avisos/records", "POST", tb, {**aviso, "user": ua})
    check("no se suplanta a otro usuario", s in (400, 403), s)
    s, _ = call("/api/collections/avisos/records", "POST", tb, {**aviso, "user": ub, "tipo": "inventado"})
    check("tipo no válido", s == 400, s)
    s, _ = call(f"/api/collections/avisos/records/{rid}", "PATCH", ta, {"texto": "otra cosa"})
    check("los avisos no se editan", s in (400, 403, 404), s)
    s, _ = call(f"/api/collections/avisos/records/{rid}", "DELETE", ta)
    check("ni se borran desde la app", s in (400, 403, 404), s)
    cod = []
    for i in range(12):
        s, _ = call("/api/collections/avisos/records", "POST", tb, {**aviso, "user": ub, "alias": "Beto"})
        cod.append(s)
    check("límite de 10 avisos por hora", 429 in cod and cod.count(200) <= 10, cod)
finally:
    if hid: call(f"/api/collections/hogares/records/{hid}", "DELETE", ta)
    for uid, tok in ((ua, ta), (ub, tb), (uc, tc)):
        call(f"/api/collections/users/records/{uid}", "DELETE", tok)
print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
sys.exit(0 if all(ok) else 1)

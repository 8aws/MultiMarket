"""Prueba de extremo a extremo de los permisos de listas compartidas.

No necesita credenciales de administrador: crea 3 usuarios de dispositivo temporales y cada uno
borra lo suyo al terminar. Respeta el rate limiting del servidor (alta: 5/min por IP; auth: 2/3 s).

  MM_URL=https://tu-servidor python3 server/tests/integration_test.py
"""
import json, os, sys, time, urllib.request, urllib.error, uuid

U = os.environ["MM_URL"].rstrip("/")


def call(path, method="GET", token=None, body=None):
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = token
    r = urllib.request.Request(U + path, method=method, headers=h,
                               data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            t = f.read().decode()
            return f.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, {"raw": t[:200]}


def mkuser(alias):
    em = f"{uuid.uuid4().hex[:10]}@device.invalid"
    pw = uuid.uuid4().hex
    s, r = call("/api/collections/users/records", "POST", None,
                {"email": em, "password": pw, "passwordConfirm": pw, "alias": alias})
    assert s == 200, ("alta de usuario", s, r)
    time.sleep(1.6)  # auth: 2 peticiones / 3 s
    s, a = call("/api/collections/users/auth-with-password", "POST", None, {"identity": em, "password": pw})
    assert s == 200, ("login", s, a)
    time.sleep(1.6)
    return a["record"]["id"], a["token"], em, pw


ok = []


def check(name, cond, extra=""):
    print(("OK   " if cond else "FAIL ") + name, extra if not cond else "")
    ok.append(bool(cond))


def main():
    ua, ta, *_ = mkuser("Ana")
    ub, tb, *_ = mkuser("Beto")
    uc, tc, *_ = mkuser("Cris")
    hogares = []  # (id, token del dueño actual) para limpiar
    try:
        s, h = call("/api/collections/hogares/records", "POST", ta, {"name": "Casa", "emoji": "🏠", "owner": ua})
        check("crear hogar", s == 200, (s, h)); hid = h.get("id"); hogares.append([hid, ta])
        code = h.get("invite_code", "")
        check("código generado por el servidor", len(code) == 10, code)
        s, _ = call("/api/collections/hogares/records", "POST", ta, {"name": "X", "owner": ua, "invite_code": "hackhackha"})
        check("cliente no fija invite_code", s in (400, 403), s)
        s, m = call(f"/api/collections/miembros/records?filter=hogar='{hid}'", "GET", ta)
        check("creador es miembro owner", s == 200 and [x["rol"] for x in m["items"]] == ["owner"], m)
        s, l = call("/api/collections/hogares/records", "GET", tb)
        check("ajeno no lista hogares", s == 200 and l["items"] == [], l)
        s, j = call("/api/mm/join", "POST", tb, {"code": code, "alias": "Beto"})
        check("unirse por código", s == 200 and j.get("id") == hid, (s, j))
        s, j = call("/api/mm/join", "POST", tc, {"code": "zzzzzzzzzz"})
        check("código inválido 404", s == 404, s)
        s, it = call("/api/collections/items/records", "POST", tb,
                     {"hogar": hid, "name": "Leche", "cold": True, "urg": 1, "done": False, "added_by": ub, "updated_ms": 1})
        check("miembro crea item", s == 200, (s, it))
        s, l = call(f"/api/collections/items/records?filter=hogar='{hid}'", "GET", ta)
        check("creador ve item del miembro", s == 200 and len(l["items"]) == 1, l)
        s, _ = call("/api/collections/items/records", "POST", tc, {"hogar": hid, "name": "Intruso", "added_by": uc})
        check("ajeno no crea item", s in (400, 403, 404), s)
        s, l = call(f"/api/collections/items/records?filter=hogar='{hid}'", "GET", tc)
        check("ajeno no ve items", s == 200 and l["items"] == [], l)
        s, _ = call("/api/collections/items/records", "POST", tb, {"hogar": hid, "name": "Falso", "added_by": ua})
        check("no se puede suplantar added_by", s in (400, 403), s)
        s, _ = call(f"/api/collections/hogares/records/{hid}", "DELETE", tb)
        check("miembro NO borra hogar", s in (403, 404), s)
        s, _ = call(f"/api/mm/hogares/{hid}/invitacion", "POST", tb)
        check("miembro NO regenera invitación", s == 403, s)
        s, r2 = call(f"/api/mm/hogares/{hid}/invitacion", "POST", ta)
        check("creador regenera invitación", s == 200 and r2.get("invite_code") != code, (s, r2))
        s, _ = call("/api/mm/join", "POST", tc, {"code": code})
        check("código antiguo deja de valer", s == 404, s)
        s, m = call(f"/api/collections/miembros/records?filter=hogar='{hid}'", "GET", ta)
        mine = {x["user"]: x["id"] for x in m["items"]}
        s, _ = call(f"/api/collections/miembros/records/{mine[ua]}", "DELETE", ta)
        check("creador no sale sin transferir", s == 400, s)
        s, _ = call(f"/api/collections/miembros/records/{mine[ub]}", "DELETE", ta)
        check("creador revoca miembro", s == 204, s)
        s, l = call(f"/api/collections/items/records?filter=hogar='{hid}'", "GET", tb)
        check("revocado ya no ve items", s == 200 and l["items"] == [], l)
        s, r2 = call(f"/api/mm/hogares/{hid}/invitacion", "POST", ta); code2 = r2["invite_code"]
        call("/api/mm/join", "POST", tb, {"code": code2})
        s, m = call(f"/api/collections/miembros/records?filter=hogar='{hid}'", "GET", ta)
        mine = {x["user"]: x["id"] for x in m["items"]}
        s, _ = call(f"/api/collections/miembros/records/{mine[ub]}", "DELETE", tb)
        check("miembro se desvincula", s == 204, s)
        s, _ = call(f"/api/collections/hogares/records/{hid}", "GET", ta)
        check("la lista origen sigue existiendo", s == 200, s)
        call("/api/mm/join", "POST", tc, {"code": code2})
        s, _ = call(f"/api/mm/hogares/{hid}/transferir", "POST", tb, {"user": uc})
        check("no-creador no transfiere", s == 403, s)
        s, _ = call(f"/api/mm/hogares/{hid}/transferir", "POST", ta, {"user": uc})
        check("creador transfiere propiedad", s == 200, s)
        hogares[0][1] = tc
        s, _ = call(f"/api/collections/hogares/records/{hid}", "DELETE", ta)
        check("ex-creador ya no borra", s in (403, 404), s)
        s, _ = call(f"/api/collections/hogares/records/{hid}", "DELETE", tc)
        check("nuevo creador borra el origen", s == 204, s)
        hogares.clear()
        for i in range(3):
            s, h3 = call("/api/collections/hogares/records", "POST", ta, {"name": f"L{i}", "owner": ua})
            hogares.append([h3.get("id"), ta])
        s, _ = call("/api/collections/hogares/records", "POST", ta, {"name": "L4", "owner": ua})
        check("límite de 3 listas", s == 400, s)
    finally:
        for hid, tok in hogares:
            if hid:
                call(f"/api/collections/hogares/records/{hid}", "DELETE", tok)
        for uid, tok in ((ua, ta), (ub, tb), (uc, tc)):
            s, _ = call(f"/api/collections/users/records/{uid}", "DELETE", tok)
            if s != 204:
                print("aviso: no se pudo borrar el usuario de prueba", uid, s)
    print(f"\n{sum(ok)}/{len(ok)} comprobaciones correctas")
    sys.exit(0 if all(ok) else 1)


main()

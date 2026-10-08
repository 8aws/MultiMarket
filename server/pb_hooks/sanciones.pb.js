/// <reference path="../pb_data/types.d.ts" />
// Sanciones: bloquea subir fotos y proponer productos a las cuentas sancionadas, y rutas de administración
// para sancionar (escalado automático) y levantar la sanción. Cada handler es autónomo (sin globales).

// ---- bloqueo al crear contenido
onRecordCreateRequest((e) => {
  const uid = e.auth ? e.auth.id : "";
  if (!uid) return e.next();
  const u = $app.findRecordById("users", uid);
  const indef = u.getBool("sancion_indef");
  const hasta = u.getDateTime("sancion_hasta");
  const activa = indef || (!hasta.isZero() && hasta.time().getTime() > Date.now());
  if (activa) {
    throw new ForbiddenError(
      indef
        ? "Tu cuenta no puede compartir contenido nuevo"
        : "Tu cuenta no puede compartir contenido hasta el " + hasta.string().substring(0, 10)
    );
  }
  e.next();
}, "fotos", "productos");

// ---- sancionar (solo superusuario): POST /api/mm/sancionar {user, motivo}
routerAdd("POST", "/api/mm/sancionar", (e) => {
  const d = e.requestInfo().body;
  const u = $app.findRecordById("users", String(d.user || ""));
  const n = (u.getInt("sanciones_n") || 0) + 1;
  let hasta = "";
  if (n >= 3) {
    u.set("sancion_indef", true);
  } else {
    const dias = n === 1 ? 7 : 30;
    hasta = new Date(Date.now() + dias * 86400000).toISOString().replace("T", " ");
    u.set("sancion_hasta", hasta);
  }
  u.set("sanciones_n", n);
  $app.save(u);
  const c = new Record($app.findCollectionByNameOrId("sanciones"));
  c.set("user", u.id);
  c.set("nivel", n);
  c.set("motivo", String(d.motivo || "").substring(0, 300));
  if (hasta) c.set("hasta", hasta);
  $app.save(c);
  return e.json(200, { nivel: n, hasta: hasta || null, indefinida: n >= 3 });
}, $apis.requireSuperuserAuth());

// ---- levantar (solo superusuario): POST /api/mm/sancion/levantar {user, reiniciar}
routerAdd("POST", "/api/mm/sancion/levantar", (e) => {
  const d = e.requestInfo().body;
  const u = $app.findRecordById("users", String(d.user || ""));
  u.set("sancion_indef", false);
  u.set("sancion_hasta", "");
  if (d.reiniciar) u.set("sanciones_n", 0);
  $app.save(u);
  return e.json(200, { ok: true });
}, $apis.requireSuperuserAuth());

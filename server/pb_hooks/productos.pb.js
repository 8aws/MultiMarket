/// <reference path="../pb_data/types.d.ts" />
// Productos nuevos de la comunidad: entran pendientes y a nombre del usuario; sin duplicados por clave.
onRecordCreateRequest((e) => {
  const auth = e.auth;
  if (!auth) throw new ForbiddenError("Inicia sesión");
  const key = String(e.record.get("key") || "").trim().toLowerCase();
  if (!key) throw new BadRequestError("Falta la clave del producto");
  e.record.set("key", key);
  const existe = $app.countRecords(
    "productos",
    $dbx.and($dbx.hashExp({ key: key }), $dbx.or($dbx.hashExp({ status: "pending" }), $dbx.hashExp({ status: "approved" })))
  );
  if (existe > 0) throw new BadRequestError("Ese producto ya está propuesto o aprobado");
  const pendientes = $app.countRecords("productos", $dbx.hashExp({ owner: auth.id, status: "pending" }));
  if (pendientes >= 60) throw new BadRequestError("Tienes demasiados productos pendientes de revisión");
  e.record.set("owner", auth.id);
  e.record.set("status", "pending");
  e.next();
}, "productos");

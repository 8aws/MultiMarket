/// <reference path="../pb_data/types.d.ts" />
// Reportes: a nombre del usuario, abiertos, y un máximo de reportes abiertos por usuario (anti-abuso).
onRecordCreateRequest((e) => {
  const auth = e.auth;
  if (!auth) throw new ForbiddenError("Inicia sesión");
  const abiertos = $app.countRecords("reportes", $dbx.hashExp({ owner: auth.id, status: "open" }));
  if (abiertos >= 40) throw new BadRequestError("Tienes demasiados reportes pendientes");
  e.record.set("owner", auth.id);
  e.record.set("status", "open");
  e.next();
}, "reportes");

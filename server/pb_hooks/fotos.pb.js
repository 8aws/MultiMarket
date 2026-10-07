/// <reference path="../pb_data/types.d.ts" />
// Fotos de la comunidad: todo entra pendiente y a nombre del usuario autenticado.
// El límite por usuario evita saturar la cola de moderación.
onRecordCreateRequest((e) => {
  const auth = e.auth;
  if (!auth) throw new ForbiddenError("Inicia sesión");
  const pendientes = $app.countRecords("fotos", $dbx.hashExp({ owner: auth.id, status: "pending" }));
  if (pendientes >= 30) throw new BadRequestError("Tienes demasiadas fotos pendientes de revisión");
  e.record.set("owner", auth.id);
  e.record.set("status", "pending");
  e.next();
}, "fotos");

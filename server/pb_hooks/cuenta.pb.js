/// <reference path="../pb_data/types.d.ts" />
// Borrado de cuenta (derecho de supresión): al eliminar un usuario,
//  - las listas que creó pasan al siguiente miembro; si estaba solo, la lista se borra;
//  - sus fotos y productos aún PENDIENTES se eliminan; lo ya aprobado queda como aportación pública sin vínculo (PocketBase vacía la relación).
// La pertenencia a listas (miembros) se borra sola en cascada.
onRecordDeleteRequest((e) => {
  const uid = e.record.id;

  const propias = $app.findRecordsByFilter("hogares", "owner = {:u}", "", 100, 0, { u: uid });
  for (const h of propias) {
    const otros = $app.findRecordsByFilter("miembros", "hogar = {:h} && user != {:u}", "id", 1, 0, { h: h.id, u: uid });
    if (otros.length > 0) {
      const nuevo = otros[0];
      h.set("owner", nuevo.get("user"));
      $app.save(h);
      nuevo.set("rol", "owner");
      $app.save(nuevo);
    } else {
      $app.delete(h); // estaba solo: se borra con sus productos, ofertas y rutas
    }
  }

  for (const col of ["fotos", "productos"]) {
    const pend = $app.findRecordsByFilter(col, "owner = {:u} && status = 'pending'", "", 500, 0, { u: uid });
    for (const r of pend) $app.delete(r);
  }

  e.next();
}, "users");

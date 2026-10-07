/// <reference path="../pb_data/types.d.ts" />
// Las colecciones creadas por migración no traen los campos de fecha: se añaden a las de moderación
// (fotos y productos) para poder ordenar y mostrar cuándo se propuso cada cosa. Idempotente.
migrate((app) => {
  for (const nombre of ["fotos", "productos"]) {
    const c = app.findCollectionByNameOrId(nombre);
    if (!c.fields.getByName("created")) c.fields.add(new AutodateField({ name: "created", onCreate: true }));
    if (!c.fields.getByName("updated")) c.fields.add(new AutodateField({ name: "updated", onCreate: true, onUpdate: true }));
    app.save(c);
  }
}, (app) => {});

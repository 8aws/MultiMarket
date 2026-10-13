/// <reference path="../pb_data/types.d.ts" />
// Marca si la observación viene de un ticket «fiable» (el ticket cuadra con su total y la línea no es dudosa).
migrate((app) => {
  const c = app.findCollectionByNameOrId("precios");
  if (!c.fields.getByName("fiable")) c.fields.add(new BoolField({ name: "fiable" }));
  app.save(c);
}, (app) => {});

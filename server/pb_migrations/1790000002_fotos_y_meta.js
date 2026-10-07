/// <reference path="../pb_data/types.d.ts" />
// - items: image_url y generic_key (foto enlazada y clave de equivalencia entre marcas).
// - fotos: fotos de producto aportadas por usuarios para la base colaborativa.
//   Entran como «pending»; se moderan por lotes desde el panel (cambiar status a approved/rejected).
//   Solo las aprobadas son públicas. El autor puede retirar la suya.
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  items.fields.add(new TextField({ name: "image_url", max: 400 }));
  items.fields.add(new TextField({ name: "generic_key", max: 200 }));
  app.save(items);

  // Solo el esqueleto: los campos y reglas los completa 1790000003 (idempotente).
  app.save(new Collection({ type: "base", name: "fotos" }));
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("fotos")); } catch (_) {}
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("image_url");
  items.fields.removeByName("generic_key");
  app.save(items);
});

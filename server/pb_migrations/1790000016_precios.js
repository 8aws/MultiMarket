/// <reference path="../pb_data/types.d.ts" />
// Precios de la comunidad (por ejemplo, los que salen de los tickets del usuario). No se exponen en bruto:
// los clientes envían observaciones y leen el precio agregado (mediana) por /api/mm/v1/precios, sin autor.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "precios" }));
  const users = app.findCollectionByNameOrId("users");
  const c = app.findCollectionByNameOrId("precios");
  for (const f of [
    new TextField({ name: "key", required: true, max: 120 }),   // código de barras o nombre normalizado
    new TextField({ name: "base", max: 120 }),                  // clave «por nombre» (sin marca ni tamaño)
    new TextField({ name: "chain", required: true, max: 40 }),
    new NumberField({ name: "price", required: true, min: 0 }),
    new TextField({ name: "name", max: 160 }),
    new TextField({ name: "dia", required: true, max: 10 }),    // YYYY-MM-DD de la observación
    new SelectField({ name: "source", required: true, maxSelect: 1, values: ["ticket", "manual"] }),
    new BoolField({ name: "outlier" }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1 }), // se vacía si se borra la cuenta
    new AutodateField({ name: "created", onCreate: true }),
  ]) c.fields.add(f);
  c.indexes = [
    "CREATE UNIQUE INDEX idx_precios_unico ON precios (owner, key, chain, dia)",
    "CREATE INDEX idx_precios_key ON precios (key, chain, dia)",
    "CREATE INDEX idx_precios_base ON precios (base, chain, dia)",
  ];
  app.save(c);
  const c2 = app.findCollectionByNameOrId("precios");
  c2.listRule = null; c2.viewRule = null; c2.createRule = null; c2.updateRule = null; c2.deleteRule = null; // solo rutas
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("precios")); } catch (_) {}
});

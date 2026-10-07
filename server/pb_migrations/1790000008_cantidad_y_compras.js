/// <reference path="../pb_data/types.d.ts" />
// - items.qty: unidades de cada producto.
// - compras: historial de compras de una lista compartida (solo añadir; la usan recompra y estadísticas).
//   Visible solo para los miembros de la lista. Se crea el esqueleto y después campos y reglas (ver 1790000003).
migrate((app) => {
  const items = app.findCollectionByNameOrId("items");
  if (!items.fields.getByName("qty")) items.fields.add(new NumberField({ name: "qty", min: 1, max: 999, onlyInt: true }));
  app.save(items);

  app.save(new Collection({ type: "base", name: "compras" }));
  const users = app.findCollectionByNameOrId("users");
  const hogares = app.findCollectionByNameOrId("hogares");
  const c = app.findCollectionByNameOrId("compras");
  for (const f of [
    new RelationField({ name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true }),
    new TextField({ name: "key", required: true, max: 120 }),
    new TextField({ name: "name", required: true, max: 160 }),
    new NumberField({ name: "qty", min: 1, max: 999, onlyInt: true }),
    new NumberField({ name: "price", min: 0 }),
    new TextField({ name: "store_id", max: 64 }),
    new TextField({ name: "store_name", max: 120 }),
    new NumberField({ name: "ms", required: true, onlyInt: true }), // instante de la compra (ms)
    new TextField({ name: "item_id", max: 32 }),
    new RelationField({ name: "by", collectionId: users.id, maxSelect: 1 }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE INDEX idx_compras_hogar_ms ON compras (hogar, ms)"];
  app.save(c);

  const soy = 'hogar.miembros_via_hogar.user ?= @request.auth.id';
  const c2 = app.findCollectionByNameOrId("compras");
  c2.listRule = '@request.auth.id != "" && ' + soy;
  c2.viewRule = '@request.auth.id != "" && ' + soy;
  c2.createRule = '@request.auth.id != "" && @request.body.hogar.miembros_via_hogar.user ?= @request.auth.id && @request.body.by = @request.auth.id';
  c2.updateRule = null; // el historial no se edita
  c2.deleteRule = soy;  // se puede retirar una compra marcada por error
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("compras")); } catch (_) {}
  const items = app.findCollectionByNameOrId("items");
  items.fields.removeByName("qty");
  app.save(items);
});

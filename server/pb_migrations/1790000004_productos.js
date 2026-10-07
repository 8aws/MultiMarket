/// <reference path="../pb_data/types.d.ts" />
// Base general de productos: los que crea un usuario y no existen en Open Food Facts.
// Entran como «pending»; solo los «approved» son públicos (y buscables por todos).
// Se crea primero el esqueleto y después campos y reglas (ver 1790000003 para el porqué).
// También `mm_estado`: pares clave/valor solo para superusuario (último aviso de moderación, etc.).
migrate((app) => {
  app.save(new Collection({ type: "base", name: "productos" }));
  app.save(new Collection({ type: "base", name: "mm_estado" }));

  const users = app.findCollectionByNameOrId("users");
  const p = app.findCollectionByNameOrId("productos");
  for (const f of [
    new TextField({ name: "key", required: true, max: 120 }), // código de barras o nombre normalizado
    new TextField({ name: "barcode", max: 32 }),
    new TextField({ name: "name", required: true, max: 160 }),
    new TextField({ name: "brand", max: 80 }),
    new TextField({ name: "quantity", max: 40 }),
    new BoolField({ name: "cold" }),
    new TextField({ name: "generic_key", max: 200 }),
    new TextField({ name: "own_chain", max: 40 }),
    new TextField({ name: "image_url", max: 400 }),
    new SelectField({ name: "status", required: true, maxSelect: 1, values: ["pending", "approved", "rejected"] }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1 }),
    new TextField({ name: "note", max: 200 }),
  ]) p.fields.add(f);
  p.indexes = [
    "CREATE INDEX idx_productos_key_status ON productos (key, status)",
    "CREATE INDEX idx_productos_status ON productos (status)",
  ];
  app.save(p);

  const e = app.findCollectionByNameOrId("mm_estado");
  e.fields.add(new TextField({ name: "k", required: true, max: 60 }));
  e.fields.add(new TextField({ name: "v", max: 400 }));
  e.indexes = ["CREATE UNIQUE INDEX idx_mm_estado_k ON mm_estado (k)"];
  app.save(e); // sin reglas: solo superusuario

  const visible = 'status = "approved" || (@request.auth.id != "" && owner = @request.auth.id)';
  const p2 = app.findCollectionByNameOrId("productos");
  p2.listRule = visible;
  p2.viewRule = visible;
  p2.createRule = '@request.auth.id != "" && @request.body.status:isset = false && @request.body.owner:isset = false && @request.body.note:isset = false';
  p2.updateRule = null; // moderación: solo superusuario
  p2.deleteRule = 'owner = @request.auth.id';
  app.save(p2);
}, (app) => {
  for (const n of ["productos", "mm_estado"]) {
    try { app.delete(app.findCollectionByNameOrId(n)); } catch (_) {}
  }
});

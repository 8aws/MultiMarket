/// <reference path="../pb_data/types.d.ts" />
// Reportes de fotos de la base común (foto asignada al producto equivocado, no es un producto, datos personales…).
// Los crea cualquier usuario con sesión; solo el administrador los resuelve desde la página de moderación.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "reportes" }));
  const users = app.findCollectionByNameOrId("users");
  const fotos = app.findCollectionByNameOrId("fotos");
  const c = app.findCollectionByNameOrId("reportes");
  for (const f of [
    new RelationField({ name: "foto", required: true, collectionId: fotos.id, maxSelect: 1, cascadeDelete: true }),
    new SelectField({
      name: "motivo", required: true, maxSelect: 1,
      values: ["producto-equivocado", "no-es-un-producto", "datos-personales", "mala-calidad", "otro"],
    }),
    new TextField({ name: "nota", max: 300 }),
    new SelectField({ name: "status", required: true, maxSelect: 1, values: ["open", "resolved", "dismissed"] }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1 }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE INDEX idx_reportes_status ON reportes (status)", "CREATE UNIQUE INDEX idx_reportes_unico ON reportes (foto, owner)"];
  app.save(c);

  const c2 = app.findCollectionByNameOrId("reportes");
  c2.listRule = '@request.auth.id != "" && owner = @request.auth.id'; // cada uno ve solo los suyos
  c2.viewRule = '@request.auth.id != "" && owner = @request.auth.id';
  c2.createRule = '@request.auth.id != "" && @request.body.status:isset = false && @request.body.owner:isset = false';
  c2.updateRule = null; // solo superusuario
  c2.deleteRule = null;
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("reportes")); } catch (_) {}
});

/// <reference path="../pb_data/types.d.ts" />
// Informes de errores de la app, SOLO si el usuario los activa en Ajustes (desactivados por defecto).
// Sin contenido de listas: versión, sistema, mensaje y traza. Solo los lee el administrador. Se borran a los 90 días.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "errores" }));
  const users = app.findCollectionByNameOrId("users");
  const c = app.findCollectionByNameOrId("errores");
  for (const f of [
    new TextField({ name: "version", max: 30 }),
    new TextField({ name: "sistema", max: 60 }),
    new TextField({ name: "mensaje", required: true, max: 400 }),
    new TextField({ name: "traza", max: 4000 }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1, cascadeDelete: true }),
    new AutodateField({ name: "created", onCreate: true }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE INDEX idx_errores_created ON errores (created)"];
  app.save(c);

  const c2 = app.findCollectionByNameOrId("errores");
  c2.listRule = null; c2.viewRule = null; c2.updateRule = null; c2.deleteRule = null; // solo superusuario
  c2.createRule = '@request.auth.id != "" && @request.body.owner:isset = false';
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("errores")); } catch (_) {}
});

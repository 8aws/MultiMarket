/// <reference path="../pb_data/types.d.ts" />
// Avisos entre miembros de una lista compartida («voy yo a comprar»). Se reciben en tiempo real y,
// cuando haya push, el mismo registro dispara la notificación nativa. Se borran solos a los 2 días.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "avisos" }));
  const users = app.findCollectionByNameOrId("users");
  const hogares = app.findCollectionByNameOrId("hogares");
  const c = app.findCollectionByNameOrId("avisos");
  for (const f of [
    new RelationField({ name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true }),
    new RelationField({ name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true }),
    new TextField({ name: "alias", max: 40 }),
    new SelectField({ name: "tipo", required: true, maxSelect: 1, values: ["voy", "otro"] }),
    new TextField({ name: "texto", max: 200 }),
    new AutodateField({ name: "created", onCreate: true }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE INDEX idx_avisos_hogar ON avisos (hogar, created)"];
  app.save(c);

  const soyMiembro = 'hogar.miembros_via_hogar.user ?= @request.auth.id';
  const c2 = app.findCollectionByNameOrId("avisos");
  c2.listRule = '@request.auth.id != "" && ' + soyMiembro;
  c2.viewRule = '@request.auth.id != "" && ' + soyMiembro;
  c2.createRule = '@request.auth.id != "" && @request.body.user = @request.auth.id && @request.body.hogar.miembros_via_hogar.user ?= @request.auth.id';
  c2.updateRule = null;
  c2.deleteRule = null;
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("avisos")); } catch (_) {}
});

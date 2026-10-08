/// <reference path="../pb_data/types.d.ts" />
// Copia opcional de la lista PRIVADA de cada usuario (la de los dispositivos, que una reinstalación borra).
// Una copia por cuenta; solo su dueño la lee y la cambia; se borra con la cuenta.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "copias" }));
  const users = app.findCollectionByNameOrId("users");
  const c = app.findCollectionByNameOrId("copias");
  for (const f of [
    new RelationField({ name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true }),
    new JSONField({ name: "datos", maxSize: 2000000 }),
    new TextField({ name: "version", max: 30 }),
    new AutodateField({ name: "created", onCreate: true }),
    new AutodateField({ name: "updated", onCreate: true, onUpdate: true }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE UNIQUE INDEX idx_copias_owner ON copias (owner)"];
  app.save(c);

  const c2 = app.findCollectionByNameOrId("copias");
  const mia = '@request.auth.id != "" && owner = @request.auth.id';
  c2.listRule = mia;
  c2.viewRule = mia;
  c2.createRule = '@request.auth.id != "" && @request.body.owner:isset = false';
  c2.updateRule = mia + ' && @request.body.owner:isset = false';
  c2.deleteRule = mia;
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("copias")); } catch (_) {}
});

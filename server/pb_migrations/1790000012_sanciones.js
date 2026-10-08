/// <reference path="../pb_data/types.d.ts" />
// Sanciones por contenido inadecuado: la cuenta sigue usando la app y leyendo la base común,
// pero no puede subir fotos ni proponer productos. Escalado: 1.ª 7 días, 2.ª 30 días, 3.ª indefinida.
// Solo el administrador (superusuario) las aplica; el usuario puede leer las suyas pero no cambiarlas.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  for (const f of [
    new NumberField({ name: "sanciones_n", min: 0, onlyInt: true }),
    new DateField({ name: "sancion_hasta" }),
    new BoolField({ name: "sancion_indef" }),
  ]) {
    if (!users.fields.getByName(f.name)) users.fields.add(f);
  }
  const bloqueo = '@request.body.sanciones_n:isset = false && @request.body.sancion_hasta:isset = false && @request.body.sancion_indef:isset = false';
  const actual = users.updateRule;
  if (!actual || actual.indexOf("sancion_hasta") < 0) {
    users.updateRule = (actual && actual.trim() ? "(" + actual + ") && " : "id = @request.auth.id && ") + bloqueo;
  }
  app.save(users);

  // registro de cada sanción (solo administrador)
  app.save(new Collection({ type: "base", name: "sanciones" }));
  const c = app.findCollectionByNameOrId("sanciones");
  for (const f of [
    new RelationField({ name: "user", collectionId: users.id, maxSelect: 1, cascadeDelete: true }),
    new NumberField({ name: "nivel", min: 1, onlyInt: true }),
    new TextField({ name: "motivo", max: 300 }),
    new DateField({ name: "hasta" }),
    new AutodateField({ name: "created", onCreate: true }),
  ]) c.fields.add(f);
  c.listRule = null; c.viewRule = null; c.createRule = null; c.updateRule = null; c.deleteRule = null;
  app.save(c);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("sanciones")); } catch (_) {}
});

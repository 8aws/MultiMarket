/// <reference path="../pb_data/types.d.ts" />
// Esquema y reglas de `fotos`. Idempotente: añade solo lo que falte.
// (Separado de 0002 porque, en PocketBase 0.40, crear la colección con campos y reglas a la vez
// que usan esos campos falla; se crean los campos primero y las reglas después.)
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const c = app.findCollectionByNameOrId("fotos");

  const campos = [
    new TextField({ name: "key", required: true, max: 120 }), // código de barras o nombre normalizado
    new TextField({ name: "barcode", max: 32 }),
    new TextField({ name: "name", max: 160 }),
    new FileField({
      name: "file", required: true, maxSelect: 1, maxSize: 3 * 1024 * 1024,
      mimeTypes: ["image/jpeg", "image/png", "image/webp"],
      thumbs: ["200x200", "600x600"],
    }),
    new BoolField({ name: "consent", required: true }), // el autor acepta publicarla sin restricciones
    new SelectField({ name: "status", required: true, maxSelect: 1, values: ["pending", "approved", "rejected"] }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1 }),
    new TextField({ name: "note", max: 200 }), // motivo del rechazo (moderación)
  ];
  for (const f of campos) {
    if (!c.fields.getByName(f.name)) c.fields.add(f);
  }
  c.indexes = [
    "CREATE INDEX idx_fotos_key_status ON fotos (key, status)",
    "CREATE INDEX idx_fotos_status ON fotos (status)",
  ];
  app.save(c);

  // Reglas (ya existen los campos). Solo lo aprobado es público; el autor ve y retira lo suyo.
  const visible = 'status = "approved" || (@request.auth.id != "" && owner = @request.auth.id)';
  const c2 = app.findCollectionByNameOrId("fotos");
  c2.listRule = visible;
  c2.viewRule = visible;
  c2.createRule = '@request.auth.id != "" && @request.body.consent = true && @request.body.status:isset = false && @request.body.owner:isset = false && @request.body.note:isset = false';
  c2.updateRule = null; // solo superusuario (moderación por lotes desde el panel)
  c2.deleteRule = 'owner = @request.auth.id';
  app.save(c2);
}, (app) => {
  // no se deshace: la 0002 elimina la colección
});

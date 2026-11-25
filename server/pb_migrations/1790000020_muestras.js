/// <reference path="../pb_data/types.d.ts" />
// Muestras de tickets para mejorar la lectura: SOLO de usuarios que el administrador autoriza (ver hook muestras.pb.js)
// y que además lo activan en la app (opción de desarrollo, desactivada por defecto). Contienen el texto leído por el OCR,
// el resultado corregido y, si el usuario lo permite, la imagen. Solo las lee el administrador. Se borran a los 90 días.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "muestras" }));
  const users = app.findCollectionByNameOrId("users");
  const c = app.findCollectionByNameOrId("muestras");
  for (const f of [
    new TextField({ name: "version", max: 30 }),
    new TextField({ name: "fuente", max: 20 }),                        // pdf · imagen · foto · texto
    new JSONField({ name: "fragmentos", maxSize: 400000 }),            // lo que devuelve el OCR (texto y posición)
    new JSONField({ name: "lineas", maxSize: 100000 }),                // las líneas ya agrupadas, por ticket
    new JSONField({ name: "resultado", maxSize: 100000 }),             // lo que se aplicó tras corregir a mano
    new FileField({
      name: "imagen", maxSelect: 1, maxSize: 8388608, protected: true,
      mimeTypes: ["image/jpeg", "image/png", "image/heic", "application/pdf"],
    }),
    new RelationField({ name: "owner", collectionId: users.id, maxSelect: 1, cascadeDelete: true }),
    new AutodateField({ name: "created", onCreate: true }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE INDEX idx_muestras_created ON muestras (created)"];
  app.save(c);

  const c2 = app.findCollectionByNameOrId("muestras");
  c2.listRule = null; c2.viewRule = null; c2.updateRule = null; c2.deleteRule = null; // solo superusuario
  c2.createRule = '@request.auth.id != "" && @request.body.owner:isset = false';
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("muestras")); } catch (_) {}
});

/// <reference path="../pb_data/types.d.ts" />
// Caché de supermercados de OpenStreetMap por celdas de 0,1° (~10 km), para no depender de los servidores públicos de Overpass.
// Contiene SOLO datos de OpenStreetMap (© colaboradores de OpenStreetMap, ODbL), sin mezclar datos propios ni de usuarios.
migrate((app) => {
  app.save(new Collection({ type: "base", name: "tiendas_cache" }));
  const c = app.findCollectionByNameOrId("tiendas_cache");
  for (const f of [
    new TextField({ name: "celda", required: true, max: 20 }),   // «lat10:lon10», p. ej. «365:-47»
    new JSONField({ name: "datos", maxSize: 2000000 }),          // lista de elementos OSM (id, tipo, coordenadas, etiquetas útiles)
    new TextField({ name: "actualizado", max: 30 }),            // ISO de la última descarga correcta de Overpass
    new NumberField({ name: "n", min: 0, onlyInt: true }),
  ]) c.fields.add(f);
  c.indexes = ["CREATE UNIQUE INDEX idx_tiendas_cache_celda ON tiendas_cache (celda)"];
  app.save(c);
  const c2 = app.findCollectionByNameOrId("tiendas_cache");
  c2.listRule = null; c2.viewRule = null; c2.createRule = null; c2.updateRule = null; c2.deleteRule = null; // solo por la ruta
  app.save(c2);
}, (app) => {
  try { app.delete(app.findCollectionByNameOrId("tiendas_cache")); } catch (_) {}
});

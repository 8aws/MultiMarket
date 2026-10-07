/// <reference path="../pb_data/types.d.ts" />
// Limpieza única: borra productos de prueba que dejó un test automático (nombre «Producto de prueba …»)
// y que quedaron huérfanos en la cola de moderación. Acotado por nombre y estado pendiente.
migrate((app) => {
  const filas = app.findRecordsByFilter("productos", "status = 'pending' && name ~ 'Producto de prueba'", "", 50, 0);
  for (const r of filas) app.delete(r);
}, (app) => {});

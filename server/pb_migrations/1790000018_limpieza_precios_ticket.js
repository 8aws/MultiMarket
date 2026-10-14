/// <reference path="../pb_data/types.d.ts" />
// Limpieza de líneas que no eran productos (saldo del club y cupón) que un lector de tickets antiguo aportó como precios.
migrate((app) => {
  const filas = app.findRecordsByFilter(
    "precios",
    "name ~ 'Saldo acumulado%' || name ~ 'P 13 QV%'",
    "", 100, 0
  );
  for (const r of filas) app.delete(r);
}, (app) => {});

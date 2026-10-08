/// <reference path="../pb_data/types.d.ts" />
// Avisos entre miembros: límite anti-spam (10 por hora y usuario) y borrado diario de los antiguos.
// Cada handler es autónomo (no comparten variables globales del fichero).
onRecordCreateRequest((e) => {
  const desde = new Date(Date.now() - 3600 * 1000).toISOString().replace("T", " ");
  const n = $app.countRecords("avisos", $dbx.exp("user = {:u} AND created > {:d}", { u: e.record.get("user"), d: desde }));
  if (n >= 10) throw new TooManyRequestsError("Demasiados avisos seguidos: espera un poco");
  e.next();
}, "avisos");

cronAdd("mm_avisos_limpieza", "30 4 * * *", () => {
  const limite = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString().replace("T", " ");
  const viejos = $app.findRecordsByFilter("avisos", "created < {:l}", "", 500, 0, { l: limite });
  for (const r of viejos) $app.delete(r);
});

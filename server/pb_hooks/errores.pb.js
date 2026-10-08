/// <reference path="../pb_data/types.d.ts" />
// Informes de errores: el autor se fija en el servidor, máximo 20 por hora y usuario, y borrado a los 90 días.
// Cada handler es autónomo (sin globales).
onRecordCreateRequest((e) => {
  const uid = e.auth ? e.auth.id : "";
  const desde = new Date(Date.now() - 3600 * 1000).toISOString().replace("T", " ");
  const n = $app.countRecords("errores", $dbx.exp("owner = {:u} AND created > {:d}", { u: uid, d: desde }));
  if (n >= 20) throw new TooManyRequestsError("Demasiados informes seguidos");
  e.record.set("owner", uid);
  e.next();
}, "errores");

cronAdd("mm_errores_limpieza", "45 4 * * *", () => {
  const limite = new Date(Date.now() - 90 * 24 * 3600 * 1000).toISOString().replace("T", " ");
  const viejos = $app.findRecordsByFilter("errores", "created < {:l}", "", 500, 0, { l: limite });
  for (const r of viejos) $app.delete(r);
});

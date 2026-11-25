/// <reference path="../pb_data/types.d.ts" />
// Muestras de tickets: solo las aceptan los usuarios que el administrador ha autorizado (lista de identificadores
// separados por comas en mm_estado, clave «muestras_usuarios»); el autor se fija en el servidor, máximo 30 por hora
// y borrado a los 90 días. Cada handler es autónomo (sin globales).
onRecordCreateRequest((e) => {
  const uid = e.auth ? e.auth.id : "";
  let ok = false;
  try {
    const estado = $app.findFirstRecordByFilter("mm_estado", "k = 'muestras_usuarios'");
    ok = uid !== "" && estado.getString("v").split(",").map((x) => x.trim()).indexOf(uid) >= 0;
  } catch (_) {}
  if (!ok) throw new ForbiddenError("Este usuario no puede enviar muestras");
  const desde = new Date(Date.now() - 3600 * 1000).toISOString().replace("T", " ");
  const n = $app.countRecords("muestras", $dbx.exp("owner = {:u} AND created > {:d}", { u: uid, d: desde }));
  if (n >= 30) throw new TooManyRequestsError("Demasiadas muestras seguidas");
  e.record.set("owner", uid);
  e.next();
}, "muestras");

cronAdd("mm_muestras_limpieza", "50 4 * * *", () => {
  const limite = new Date(Date.now() - 90 * 24 * 3600 * 1000).toISOString().replace("T", " ");
  const viejas = $app.findRecordsByFilter("muestras", "created < {:l}", "", 200, 0, { l: limite });
  for (const r of viejas) $app.delete(r); // borra también el fichero de la imagen
});

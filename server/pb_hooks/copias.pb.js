/// <reference path="../pb_data/types.d.ts" />
// Copias de la lista privada: el dueño se fija en el servidor (el cliente no puede escribirlo).
onRecordCreateRequest((e) => {
  e.record.set("owner", e.auth ? e.auth.id : "");
  e.next();
}, "copias");

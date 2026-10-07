/// <reference path="../pb_data/types.d.ts" />
// Avisa por correo al administrador cuando hay contenido pendiente de moderar:
//   - con 10 o más elementos pendientes: como mucho cada 6 horas;
//   - con menos (pero al menos 1): como mucho cada 2 días.
// El destinatario son los superusuarios (no se guarda ningún correo en el repositorio).
// Cada handler es autónomo (los hooks de PocketBase no comparten variables de nivel superior).
cronAdd("mm_aviso_moderacion", "0 * * * *", () => {
  try {
    const nFotos = $app.countRecords("fotos", $dbx.hashExp({ status: "pending" }));
    const nProductos = $app.countRecords("productos", $dbx.hashExp({ status: "pending" }));
    const nReportes = $app.countRecords("reportes", $dbx.hashExp({ status: "open" }));
    const total = nFotos + nProductos + nReportes;
    if (total < 1) return;

    let estado = null;
    try { estado = $app.findFirstRecordByFilter("mm_estado", "k = 'ultimo_aviso'"); } catch (_) {}
    const ultimo = estado ? Number(estado.get("v")) || 0 : 0;
    const horas = (Date.now() - ultimo) / 3600000;
    const toca = (total >= 10 && horas >= 6) || horas >= 48;
    if (!toca) return;

    const ajustes = $app.settings();
    const destinos = $app.findAllRecords("_superusers").map((r) => ({ address: r.email() }));
    if (destinos.length === 0) return;
    const url = String(ajustes.meta.appURL || "").replace(/\/+$/, "") + "/moderacion/";
    const mensaje = new MailerMessage({
      from: { address: ajustes.meta.senderAddress, name: ajustes.meta.senderName },
      to: destinos,
      subject: "MultiMarket: " + total + " elemento" + (total === 1 ? "" : "s") + " pendiente" + (total === 1 ? "" : "s") + " de moderar",
      html:
        "<p>Hay contenido nuevo de la comunidad esperando revisión:</p>" +
        "<ul><li>Fotos: <b>" + nFotos + "</b></li><li>Productos nuevos: <b>" + nProductos + "</b></li><li>Reportes de fotos: <b>" + nReportes + "</b></li></ul>" +
        '<p><a href="' + url + '">Abrir la página de moderación</a></p>',
    });
    $app.newMailClient().send(mensaje);

    if (!estado) {
      estado = new Record($app.findCollectionByNameOrId("mm_estado"));
      estado.set("k", "ultimo_aviso");
    }
    estado.set("v", String(Date.now()));
    $app.save(estado);
    console.log("[mm] aviso de moderación enviado: " + total + " pendientes");
  } catch (err) {
    console.log("[mm] aviso de moderación falló: " + err);
  }
});

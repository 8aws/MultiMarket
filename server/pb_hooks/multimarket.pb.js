/// <reference path="../pb_data/types.d.ts" />
// MultiMarket — lógica de hogares: límite de 3, código de invitación, unirse,
// regenerar, transferir propiedad y salida ordenada del creador.
// Nota: cada callback es autónomo (los hooks de PB no comparten funciones de nivel superior).

// Alfabeto del código: sin caracteres ambiguos (0/o, 1/l/i). Máximo de listas por usuario: 3.

// --- Crear hogar: valida límite, fija owner y genera el código
onRecordCreateRequest((e) => {
  const auth = e.auth;
  if (!auth) throw new ForbiddenError("Inicia sesión");
  const n = $app.countRecords("miembros", $dbx.hashExp({ user: auth.id }));
  if (n >= 3) throw new BadRequestError("Máximo 3 listas compartidas");
  e.record.set("owner", auth.id);
  e.record.set("invite_code", $security.randomStringWithAlphabet(10, "abcdefghjkmnpqrstuvwxyz23456789"));
  e.next();
}, "hogares");

// --- Tras crear el hogar, el creador entra como miembro `owner`
onRecordCreateRequest((e) => {
  e.next();
  const col = $app.findCollectionByNameOrId("miembros");
  const m = new Record(col);
  m.set("hogar", e.record.id);
  m.set("user", e.record.get("owner"));
  m.set("rol", "owner");
  m.set("alias", (e.auth && e.auth.get("alias")) || "");
  $app.save(m);
}, "hogares");

// --- Unirse por código
routerAdd("POST", "/api/mm/join", (e) => {
  const body = e.requestInfo().body || {};
  const code = String(body.code || "").trim().toLowerCase();
  if (code.length < 6) throw new BadRequestError("Código no válido");
  let hogar;
  try {
    hogar = $app.findFirstRecordByFilter("hogares", "invite_code = {:code}", { code: code });
  } catch (_) {
    throw new NotFoundError("Código no válido o caducado");
  }
  const uid = e.auth.id;
  const ya = $app.countRecords("miembros", $dbx.hashExp({ hogar: hogar.id, user: uid }));
  if (ya === 0) {
    if ($app.countRecords("miembros", $dbx.hashExp({ user: uid })) >= 3) {
      throw new BadRequestError("Máximo 3 listas compartidas");
    }
    const m = new Record($app.findCollectionByNameOrId("miembros"));
    m.set("hogar", hogar.id);
    m.set("user", uid);
    m.set("rol", "member");
    m.set("alias", String(body.alias || e.auth.get("alias") || "").slice(0, 40));
    $app.save(m);
  }
  return e.json(200, { id: hogar.id, name: hogar.get("name"), emoji: hogar.get("emoji") });
}, $apis.requireAuth());

// --- Regenerar invitación (solo el creador): el código anterior deja de valer
routerAdd("POST", "/api/mm/hogares/{id}/invitacion", (e) => {
  const hogar = $app.findRecordById("hogares", e.request.pathValue("id"));
  if (hogar.get("owner") !== e.auth.id) throw new ForbiddenError("Solo el creador");
  const code = $security.randomStringWithAlphabet(10, "abcdefghjkmnpqrstuvwxyz23456789");
  hogar.set("invite_code", code);
  $app.save(hogar);
  return e.json(200, { invite_code: code });
}, $apis.requireAuth());

// --- Transferir propiedad a otro miembro (solo el creador)
routerAdd("POST", "/api/mm/hogares/{id}/transferir", (e) => {
  const hogar = $app.findRecordById("hogares", e.request.pathValue("id"));
  if (hogar.get("owner") !== e.auth.id) throw new ForbiddenError("Solo el creador");
  const nuevo = String((e.requestInfo().body || {}).user || "");
  let destino;
  try {
    destino = $app.findFirstRecordByFilter("miembros", "hogar = {:h} && user = {:u}", { h: hogar.id, u: nuevo });
  } catch (_) {
    throw new BadRequestError("Ese usuario no es miembro");
  }
  const actual = $app.findFirstRecordByFilter("miembros", "hogar = {:h} && user = {:u}", { h: hogar.id, u: e.auth.id });
  $app.runInTransaction((tx) => {
    hogar.set("owner", nuevo);
    tx.save(hogar);
    destino.set("rol", "owner");
    tx.save(destino);
    actual.set("rol", "member");
    tx.save(actual);
  });
  return e.json(200, { ok: true });
}, $apis.requireAuth());

// --- El creador no puede irse sin transferir; si está solo, la lista se borra con él
onRecordDeleteRequest((e) => {
  if (e.record.get("rol") === "owner") {
    const hogarId = e.record.get("hogar");
    const otros = $app.countRecords("miembros", $dbx.and($dbx.hashExp({ hogar: hogarId }), $dbx.not($dbx.hashExp({ user: e.record.get("user") }))));
    if (otros > 0) throw new BadRequestError("Transfiere la propiedad antes de salir");
    e.next();
    try { $app.delete($app.findRecordById("hogares", hogarId)); } catch (_) {}
    return;
  }
  e.next();
}, "miembros");

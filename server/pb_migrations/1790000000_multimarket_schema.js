/// <reference path="../pb_data/types.d.ts" />
// MultiMarket — esquema de listas compartidas (ver docs/SYNC.md).
// Colecciones: hogares, miembros, items, ofertas, rutas (+ campo alias en users).

migrate((app) => {
  const users = app.findCollectionByNameOrId("users");

  // ---- alias visible del usuario (sin datos personales)
  users.fields.add(new TextField({ name: "alias", max: 40 }));
  app.save(users);

  // Regla reutilizable: el usuario es miembro del hogar referenciado por `hogar`
  const soyMiembro = 'hogar.miembros_via_hogar.user ?= @request.auth.id';
  // ... y al crear, el hogar viene en el body
  const soyMiembroBody = '@request.body.hogar.miembros_via_hogar.user ?= @request.auth.id';

  // ---- hogares
  const hogares = new Collection({
    type: "base",
    name: "hogares",
    fields: [
      { type: "text", name: "name", required: true, max: 40 },
      { type: "text", name: "emoji", max: 8 },
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1 },
      { type: "text", name: "invite_code" }, // lo genera el hook; el cliente no puede fijarlo
    ],
    indexes: ["CREATE UNIQUE INDEX idx_hogares_invite ON hogares (invite_code)"],
    // list/view se fijan más abajo: necesitan la relación inversa miembros_via_hogar
    listRule: null,
    viewRule: null,
    createRule: '@request.auth.id != "" && @request.body.owner = @request.auth.id && @request.body.invite_code:isset = false',
    updateRule: 'owner = @request.auth.id && @request.body.owner:isset = false && @request.body.invite_code:isset = false',
    deleteRule: 'owner = @request.auth.id', // solo el creador borra la lista de origen
  });
  app.save(hogares);

  // ---- miembros (se crean solo desde hooks: al crear el hogar y al unirse por código)
  const miembros = new Collection({
    type: "base",
    name: "miembros",
    fields: [
      { type: "relation", name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "alias", max: 40 },
      { type: "select", name: "rol", required: true, maxSelect: 1, values: ["owner", "member"] },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_miembros_hogar_user ON miembros (hogar, user)"],
    listRule: '@request.auth.id != "" && ' + soyMiembro,
    viewRule: '@request.auth.id != "" && ' + soyMiembro,
    createRule: null,
    // solo el propio alias; rol/hogar/user no se tocan desde la API
    updateRule: 'user = @request.auth.id && @request.body.rol:isset = false && @request.body.hogar:isset = false && @request.body.user:isset = false',
    // desvincularse (propia fila) o revocar (el creador borra cualquiera)
    deleteRule: 'user = @request.auth.id || hogar.owner = @request.auth.id',
  });
  app.save(miembros);

  // ahora que existe `miembros`, hogares puede usar la relación inversa
  const hogaresFinal = app.findCollectionByNameOrId("hogares");
  const visible = '@request.auth.id != "" && (owner = @request.auth.id || miembros_via_hogar.user ?= @request.auth.id)';
  hogaresFinal.listRule = visible;
  hogaresFinal.viewRule = visible;
  app.save(hogaresFinal);

  const reglasHogar = {
    listRule: '@request.auth.id != "" && ' + soyMiembro,
    viewRule: '@request.auth.id != "" && ' + soyMiembro,
    createRule: '@request.auth.id != "" && ' + soyMiembroBody,
    updateRule: soyMiembro + ' && @request.body.hogar:isset = false',
    deleteRule: soyMiembro,
  };

  // ---- items
  app.save(new Collection({
    type: "base",
    name: "items",
    fields: [
      { type: "relation", name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "name", required: true, max: 120 },
      { type: "text", name: "barcode", max: 32 },
      { type: "bool", name: "cold" },
      { type: "number", name: "urg", min: 1, max: 3, onlyInt: true },
      { type: "bool", name: "done" },
      { type: "text", name: "store_id", max: 64 },
      { type: "number", name: "price", min: 0 },
      { type: "relation", name: "added_by", collectionId: users.id, maxSelect: 1 },
      { type: "number", name: "updated_ms", onlyInt: true }, // último cambio gana (reloj del cliente)
    ],
    indexes: ["CREATE INDEX idx_items_hogar ON items (hogar)"],
    ...reglasHogar,
    createRule: reglasHogar.createRule + ' && @request.body.added_by = @request.auth.id',
  }));

  // ---- ofertas
  app.save(new Collection({
    type: "base",
    name: "ofertas",
    fields: [
      { type: "relation", name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "key", required: true, max: 120 },
      { type: "text", name: "name", required: true, max: 120 },
      { type: "text", name: "chain", required: true, max: 40 },
      { type: "number", name: "price", required: true, min: 0 },
      { type: "text", name: "until", required: true, max: 10 }, // AAAA-MM-DD
    ],
    indexes: ["CREATE UNIQUE INDEX idx_ofertas_unica ON ofertas (hogar, key, chain)"],
    ...reglasHogar,
  }));

  // ---- rutas («voy yo a este súper»)
  app.save(new Collection({
    type: "base",
    name: "rutas",
    fields: [
      { type: "relation", name: "hogar", required: true, collectionId: hogares.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "chain", required: true, max: 40 },
      { type: "relation", name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "day", required: true, max: 10 },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_rutas_unica ON rutas (hogar, chain, day)"],
    ...reglasHogar,
    createRule: reglasHogar.createRule + ' && @request.body.user = @request.auth.id',
    updateRule: 'user = @request.auth.id && @request.body.hogar:isset = false',
    deleteRule: 'user = @request.auth.id',
  }));
}, (app) => {
  for (const n of ["rutas", "ofertas", "items", "miembros", "hogares"]) {
    try { app.delete(app.findCollectionByNameOrId(n)); } catch (_) {}
  }
  const users = app.findCollectionByNameOrId("users");
  users.fields.removeByName("alias");
  app.save(users);
});

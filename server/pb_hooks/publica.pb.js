/// <reference path="../pb_data/types.d.ts" />
// API pública de solo lectura de la base común de productos (sin sesión, sin clave).
//   GET /api/mm/v1/productos?barcode=8480000106483
//   GET /api/mm/v1/productos?q=leche&page=1&per=20
// Solo devuelve productos APROBADOS por moderación y nunca datos del autor.
// Límite: 60 peticiones por minuto y por IP (429 + Retry-After); máximo 50 resultados por página.
routerAdd("GET", "/api/mm/v1/productos", (e) => {
  const MM_LIMITE = 60; // los manejadores no ven variables globales del fichero
  const ahora = Date.now();
  const bucket = Math.floor(ahora / 60000);
  const ip = e.realIP();
  const st = $app.store();
  const k = "rl:" + ip + ":" + bucket;
  const n = (st.get(k) || 0) + 1;
  st.set(k, n);
  st.remove("rl:" + ip + ":" + (bucket - 1)); // no acumular ventanas viejas
  if (n > MM_LIMITE) {
    e.response.header().set("Retry-After", String(Math.ceil((60000 - (ahora % 60000)) / 1000)));
    return e.json(429, { message: "Demasiadas peticiones: máximo 60 por minuto" });
  }

  const q = e.request.url.query();
  const barcode = (q.get("barcode") || "").trim();
  const texto = (q.get("q") || "").trim();
  if (!barcode && texto.length < 2) {
    return e.json(400, { message: "Indica barcode o q (mínimo 2 letras)" });
  }
  const per = Math.max(1, Math.min(50, parseInt(q.get("per") || "20", 10) || 20));
  const page = Math.max(1, parseInt(q.get("page") || "1", 10) || 1);

  let filtro = "status = 'approved'";
  const params = {};
  if (barcode) {
    filtro += " && barcode = {:b}";
    params.b = barcode;
  } else {
    filtro += " && (name ~ {:t} || brand ~ {:t})";
    params.t = texto;
  }
  let filas;
  try {
    filas = $app.findRecordsByFilter("productos", filtro, "name", per + 1, (page - 1) * per, params);
  } catch (err) {
    return e.json(500, { message: "Error de consulta: " + err });
  }
  const hayMas = filas.length > per;
  const items = filas.slice(0, per).map((r) => {
    let foto = null;
    try {
      const f = $app.findFirstRecordByFilter("fotos", "key = {:k} && status = 'approved'", { k: r.get("key") });
      const nombre = f.get("file");
      foto = {
        url: "/api/files/fotos/" + f.id + "/" + nombre,
        miniatura: "/api/files/fotos/" + f.id + "/" + nombre + "?thumb=200x200",
      };
    } catch (_) {}
    return {
      barcode: r.get("barcode") || null,
      name: r.get("name"),
      brand: r.get("brand") || null,
      quantity: r.get("quantity") || null,
      cold: !!r.get("cold"),
      genericKey: r.get("generic_key") || null,
      ownChain: r.get("own_chain") || null,
      imageUrl: r.get("image_url") || null,
      foto: foto,
    };
  });
  e.response.header().set("Cache-Control", "public, max-age=300");
  e.response.header().set("Access-Control-Allow-Origin", "*");
  return e.json(200, { page: page, perPage: per, hasMore: hayMas, items: items });
});

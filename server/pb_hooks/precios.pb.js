/// <reference path="../pb_data/types.d.ts" />
// Precios de la comunidad. Escritura: POST /api/mm/v1/precios (con sesión). Lectura: GET (pública, con límite por IP).
// Cada handler es autónomo (los manejadores no ven globales del fichero).

routerAdd("POST", "/api/mm/v1/precios", (e) => {
  const uid = e.auth.id;
  const d = e.requestInfo().body;
  const lista = Array.isArray(d.items) ? d.items.slice(0, 50) : [];
  if (lista.length === 0) return e.json(400, { message: "Sin precios" });

  const desde = new Date(Date.now() - 24 * 3600 * 1000).toISOString().replace("T", " ");
  const hoy = $app.countRecords("precios", $dbx.exp("owner = {:u} AND created > {:d}", { u: uid, d: desde }));
  if (hoy >= 400) return e.json(429, { message: "Demasiados precios hoy" });

  const col = $app.findCollectionByNameOrId("precios");
  const limite90 = new Date(Date.now() - 90 * 86400000).toISOString().substring(0, 10);
  let guardados = 0, omitidos = 0;
  for (const it of lista) {
    try {
      const key = String(it.key || "").trim().toLowerCase().substring(0, 120);
      const chain = String(it.chain || "").trim().toLowerCase().substring(0, 40);
      const price = Number(it.price);
      const dia = String(it.fecha || "").substring(0, 10);
      if (!key || !chain || !(price >= 0.05 && price <= 500) || !/^\d{4}-\d{2}-\d{2}$/.test(dia)) { omitidos++; continue; }
      const hoyStr = new Date().toISOString().substring(0, 10);
      if (dia > hoyStr || dia < limite90) { omitidos++; continue; } // ni futuras ni de hace más de 90 días

      // valor atípico respecto a lo que ya se sabe (mediana de las últimas observaciones)
      let outlier = false;
      const previas = $app.findRecordsByFilter("precios", "key = {:k} && chain = {:c} && outlier = false", "-dia", 15, 0, { k: key, c: chain });
      if (previas.length >= 3) {
        const v = previas.map((r) => r.getFloat("price")).sort((a, b) => a - b);
        const med = v[Math.floor(v.length / 2)];
        if (price > med * 3 || price < med / 3) outlier = true;
      }
      const r = new Record(col);
      r.set("key", key);
      r.set("base", String(it.base || "").trim().toLowerCase().substring(0, 120));
      r.set("chain", chain);
      r.set("price", Math.round(price * 100) / 100);
      r.set("name", String(it.name || "").substring(0, 160));
      r.set("dia", dia);
      r.set("source", "ticket");
      r.set("outlier", outlier);
      r.set("owner", uid);
      $app.save(r);
      guardados++;
    } catch (_) { omitidos++; } // duplicado (mismo día, producto y cadena) u otro fallo: se ignora
  }
  return e.json(200, { guardados: guardados, omitidos: omitidos });
}, $apis.requireAuth());

routerAdd("GET", "/api/mm/v1/precios", (e) => {
  // límite por IP: 60/min (contador propio)
  const ahora = Date.now();
  const bucket = Math.floor(ahora / 60000);
  const ip = e.realIP();
  const st = $app.store();
  const k = "rlp:" + ip + ":" + bucket;
  const n = (st.get(k) || 0) + 1;
  st.set(k, n);
  st.remove("rlp:" + ip + ":" + (bucket - 1));
  if (n > 60) {
    e.response.header().set("Retry-After", String(Math.ceil((60000 - (ahora % 60000)) / 1000)));
    return e.json(429, { message: "Demasiadas peticiones: máximo 60 por minuto" });
  }

  const q = e.request.url.query();
  const keys = (q.get("keys") || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean).slice(0, 40);
  const bases = (q.get("bases") || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean).slice(0, 40);
  if (keys.length === 0 && bases.length === 0) return e.json(400, { message: "Indica keys o bases" });
  const desde = new Date(Date.now() - 120 * 86400000).toISOString().substring(0, 10);

  const agregar = (campo, valor) => {
    const filas = $app.findRecordsByFilter("precios", campo + " = {:v} && outlier = false && dia >= {:d}", "-dia", 100, 0, { v: valor, d: desde });
    const porCadena = {};
    for (const r of filas) {
      const c = r.getString("chain");
      (porCadena[c] = porCadena[c] || []).push({ p: r.getFloat("price"), d: r.getString("dia") });
    }
    const out = [];
    for (const c of Object.keys(porCadena)) {
      const l = porCadena[c];
      const v = l.map((x) => x.p).sort((a, b) => a - b);
      out.push({ chain: c, price: v[Math.floor(v.length / 2)], n: l.length, fecha: l[0].d });
    }
    return out;
  };
  const items = [];
  for (const kk of keys) for (const r of agregar("key", kk)) items.push({ key: kk, ...r });
  for (const bb of bases) for (const r of agregar("base", bb)) items.push({ base: bb, ...r });
  e.response.header().set("Cache-Control", "public, max-age=120");
  return e.json(200, { items: items });
});

// limpieza: observaciones de las pruebas automáticas (clave «test-…») y de más de un año
cronAdd("mm_precios_limpieza", "50 4 * * *", () => {
  const viejo = new Date(Date.now() - 365 * 86400000).toISOString().substring(0, 10);
  const basura = $app.findRecordsByFilter("precios", "key ~ 'test-%' || dia < {:d}", "", 500, 0, { d: viejo });
  for (const r of basura) $app.delete(r);
});

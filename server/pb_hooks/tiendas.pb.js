/// <reference path="../pb_data/types.d.ts" />
// Supermercados de OpenStreetMap con caché propia (respaldo si los servidores públicos de Overpass fallan).
//   GET /api/mm/v1/tiendas?lat=36.5&lon=-4.6&r=5      (r en km, máx. 15)
// Por celdas de 0,1°; una celda se vuelve a pedir a Overpass si tiene más de 30 días o no existe. Si Overpass falla se sirve la
// copia antigua. Datos © colaboradores de OpenStreetMap (ODbL). Límite: 30 peticiones/min por IP.
// Cada handler es autónomo (los manejadores no ven globales del fichero).
routerAdd("GET", "/api/mm/v1/tiendas", (e) => {
  const ahora = Date.now();
  const bucket = Math.floor(ahora / 60000);
  const ip = e.realIP();
  const st = $app.store();
  const kl = "rlt:" + ip + ":" + bucket;
  const nn = (st.get(kl) || 0) + 1;
  st.set(kl, nn);
  st.remove("rlt:" + ip + ":" + (bucket - 1));
  if (nn > 30) {
    e.response.header().set("Retry-After", String(Math.ceil((60000 - (ahora % 60000)) / 1000)));
    return e.json(429, { message: "Demasiadas peticiones: máximo 30 por minuto" });
  }

  const q = e.request.url.query();
  const lat = parseFloat(q.get("lat")), lon = parseFloat(q.get("lon"));
  const r = Math.min(15, Math.max(0.5, parseFloat(q.get("r") || "5")));
  if (!isFinite(lat) || !isFinite(lon) || lat < 27 || lat > 44.5 || lon < -19 || lon > 5) {
    return e.json(400, { message: "Indica lat y lon dentro de España" });
  }

  const dLat = r / 111.32, dLon = r / (111.32 * Math.cos((lat * Math.PI) / 180));
  const i0 = Math.floor((lat - dLat) * 10), i1 = Math.floor((lat + dLat) * 10);
  const j0 = Math.floor((lon - dLon) * 10), j1 = Math.floor((lon + dLon) * 10);
  const col = $app.findCollectionByNameOrId("tiendas_cache");
  const servidores = ["overpass.openstreetmap.fr", "overpass-api.de", "z.overpass-api.de", "overpass.kumi.systems", "overpass.private.coffee"];
  const inicio = Date.now();
  const MAX_EDAD = 30 * 86400000;

  const descargar = (i, j) => {
    const s = i / 10, w = j / 10, n = (i + 1) / 10, o = (j + 1) / 10;
    const consulta = '[out:json][timeout:25];nwr["shop"="supermarket"](' + s + "," + w + "," + n + "," + o + ");out center tags;";
    for (const h of servidores) {
      if (Date.now() - inicio > 22000) break; // presupuesto total por petición
      try {
        const res = $http.send({
          url: "https://" + h + "/api/interpreter",
          method: "POST",
          body: "data=" + encodeURIComponent(consulta),
          headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "MultiMarket/1.0 (+https://multimarket.uverse.es)" },
          timeout: 12,
        });
        if (res.statusCode !== 200 || !res.json || !Array.isArray(res.json.elements)) continue;
        if (res.json.remark && /runtime error|timed out/i.test(String(res.json.remark))) continue;
        return res.json.elements.map((x) => {
          const t = x.tags || {};
          const c = x.center || {};
          return {
            t: x.type, id: x.id,
            lat: x.lat !== undefined ? x.lat : c.lat, lon: x.lon !== undefined ? x.lon : c.lon,
            name: t.name || null, brand: t.brand || null, operator: t.operator || null, opening_hours: t.opening_hours || null,
          };
        }).filter((x) => x.lat !== undefined && x.lon !== undefined);
      } catch (_) { /* siguiente servidor */ }
    }
    return null;
  };

  let incompleto = false, masAntigua = null, items = [], descargas = 0;
  for (let i = i0; i <= i1; i++) {
    for (let j = j0; j <= j1; j++) {
      const clave = i + ":" + j;
      let rec = null;
      try { rec = $app.findFirstRecordByFilter("tiendas_cache", "celda = {:c}", { c: clave }); } catch (_) {}
      const edad = rec ? ahora - (Date.parse(rec.getString("actualizado")) || 0) : Infinity;
      if ((!rec || edad > MAX_EDAD) && descargas < 3) {
        descargas++;
        const datos = descargar(i, j);
        if (datos) {
          if (!rec) { rec = new Record(col); rec.set("celda", clave); }
          rec.set("datos", datos);
          rec.set("n", datos.length);
          rec.set("actualizado", new Date().toISOString());
          $app.save(rec);
        }
      }
      if (rec && rec.get("datos")) {
        const arr = JSON.parse(rec.getString("datos"));
        for (const x of arr) items.push(x);
        const a = rec.getString("actualizado");
        if (!masAntigua || a < masAntigua) masAntigua = a;
      } else {
        incompleto = true; // esta celda no se pudo obtener ni había copia
      }
    }
  }
  // dentro del radio pedido
  const km = (a, b, c, d) => {
    const R = 6371, p = Math.PI / 180;
    const x = Math.sin((c - a) * p / 2) ** 2 + Math.cos(a * p) * Math.cos(c * p) * Math.sin((d - b) * p / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(x));
  };
  items = items.filter((x) => km(lat, lon, x.lat, x.lon) <= r);
  e.response.header().set("Cache-Control", "public, max-age=600");
  return e.json(200, {
    atribucion: "© colaboradores de OpenStreetMap (ODbL, https://www.openstreetmap.org/copyright)",
    actualizado: masAntigua,
    incompleto: incompleto,
    items: items,
  });
});

// limpieza: celdas sin datos útiles de más de un año (no debería ocurrir; evita acumular basura)
cronAdd("mm_tiendas_cache_limpieza", "20 5 * * 0", () => {
  const viejo = new Date(Date.now() - 365 * 86400000).toISOString();
  const filas = $app.findRecordsByFilter("tiendas_cache", "actualizado < {:l} || n = 0", "", 200, 0, { l: viejo });
  for (const f of filas) $app.delete(f);
});

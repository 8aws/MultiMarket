# API pública de la base común

Solo lectura, sin sesión y sin clave. Devuelve únicamente productos **aprobados por moderación** y nunca datos de quien los aportó.

```
GET /api/mm/v1/productos?barcode=8480000106483
GET /api/mm/v1/productos?q=leche&page=1&per=20
```

| Parámetro | |
|---|---|
| `barcode` | código de barras exacto |
| `q` | texto en nombre o marca (mínimo 2 letras) |
| `page`, `per` | paginación; `per` máximo 50 |

Respuesta: `{ page, perPage, hasMore, items: [{ barcode, name, brand, quantity, cold, genericKey, ownChain, imageUrl, foto: { url, miniatura } }] }`.
Las rutas de `foto` son relativas al servidor.

**Límite:** 60 peticiones por minuto y por IP; al pasarlo responde `429` con `Retry-After`. Las respuestas se pueden cachear 5 minutos.

Las aportaciones de la comunidad se publican sin restricciones (el autor lo acepta al subirlas). Los datos que provienen de Open Food Facts u Open Prices conservan su licencia ODbL.

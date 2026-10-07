# Base de precios propia (diseño)

Objetivo: una base abierta, por país, alimentada por Open Prices y por los usuarios de MultiMarket,
que otros puedan reutilizar sin depender de terceros.

## Open Prices: cuenta y licencia
- **Leer** es libre y sin cuenta (`GET /api/v1/prices`, `/locations`, `/products`).
- **Publicar** (`POST /api/v1/prices`) exige un token Bearer **de una cuenta de usuario** de
  Open Food Facts y un `proof_id` (foto del ticket o etiqueta). Por eso la contribución debe ser
  **una cuenta por persona**, con su propio inicio de sesión; una cuenta genérica de la app
  rompería la atribución y se expondría a un bloqueo.
- Los datos son ODbL: se pueden copiar a una base propia con atribución, y la base derivada
  debe seguir siendo abierta (ODbL) — encaja con el objetivo.

## Esquema (PostgreSQL / SQLite)
```sql
country(code text primary key);            -- 'ES', 'PT'...  segmentación por país
chain(id serial primary key, country text references country, slug text, name text);
store(id serial primary key, country text, chain_id int, osm_type text, osm_id bigint,
      name text, lat double precision, lon double precision, unique(osm_type, osm_id));
product(barcode text primary key, name text, brand text, cold boolean, own_chain_id int,
        image_url text null);               -- imagen opcional
price(id bigserial primary key, country text not null, barcode text, name_free text,
      chain_id int, store_id int null, amount numeric(8,2) not null, currency text default 'EUR',
      observed_on date not null, valid_until date null,      -- ofertas con caducidad
      source text not null,                 -- 'open_prices' | 'user' | 'import'
      source_ref text null, user_hash text null,             -- sin datos personales
      image_url text null);                 -- foto opcional
create index on price(country, barcode, chain_id, observed_on desc);
```
Todo lleva `country`: se añade otro país insertando su fila y sus cadenas.

## Flujo
1. **Sincronizar**: trabajo periódico que consulta Open Prices por país y códigos de barras
   conocidos, guarda con `source='open_prices'`.
2. **Aportaciones de usuarios**: al marcar comprado y anotar precio, la app puede enviarlo
   (opt-in) con `source='user'`. Para subirlo también a Open Prices haría falta la sesión del
   propio usuario y una foto.
3. **Verificación**: un precio gana confianza cuando varios usuarios coinciden en un rango o
   pasa de reciente; se muestran siempre fecha y origen.
4. **Publicar**: volcado periódico (CSV/Parquet por país) como release de GitHub, licencia ODbL,
   más API de solo lectura opcional.

## Alojamiento gratuito sugerido
Primero solo el volcado estático en GitHub Releases (coste cero). Cuando haya escrituras de
usuarios: Supabase (Postgres, tier gratuito) o Cloudflare D1, con límite de peticiones y sin
guardar identificadores personales.

## Pendiente de decidir
- Umbral de confianza para mostrar un precio como «verificado».
- Política de imágenes (peso máximo, moderación, licencia de la foto).

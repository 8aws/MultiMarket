# Listas compartidas (diseño)

Estado: **la app ya tiene listas múltiples en local** (privada + hasta 3 hogares). Falta el servidor.
Servicios previstos, todos autoalojados y abiertos: **PocketBase** (datos + tiempo real), **ntfy**
(avisos push) y **SMTP con relay** (recuperación de cuenta, opcional).

## Reglas de producto
- Sin hogar, todo es privado y vive solo en el dispositivo. La app funciona entera sin servidor.
- Máximo 3 hogares además de la privada. El hogar activo se elige junto al título.
- Compartido por hogar: productos, urgencia, tienda, comprado, quién lo añadió, ofertas, rutas («voy yo»).
- Personal: temporizador de frío, bolsa, tarjetas visibles, notificaciones, ubicación y súper activos.
- Offline primero: todo se escribe en local y se sube en cola; en conflicto gana el último cambio
  **de cada producto** (`client_updated`).

## Permisos: creador y miembros
| Acción | Creador | Miembro |
|---|---|---|
| Añadir / editar / marcar productos | sí | sí |
| **Desvincular** la lista de su dispositivo (deja de recibirla; la lista sigue para los demás) | sí* | sí |
| **Borrar la lista de origen** (desaparece para todos) | **sí** | no |
| Ver miembros | sí | sí |
| **Revocar** a un miembro (pierde el acceso y se borra su copia local al sincronizar) | **sí** | no |
| **Reenviar / regenerar invitación** (el código anterior deja de valer) | **sí** | no |

\* Si el creador se desvincula sin borrar, debe antes **transferir la propiedad** a otro miembro; si no hay más
miembros, desvincular equivale a borrar (con confirmación).

Implementación en PocketBase: `hogares.deleteRule = owner = @request.auth.id`; `miembros.deleteRule` permite
borrar la propia fila (desvincular) o cualquiera si eres `owner` del hogar (revocar). Regenerar invitación =
hook que reescribe `invite_code`. Un miembro revocado recibe 403 en la siguiente sincronización y la app
elimina la copia local y avisa. En la app el modelo ya guarda `Hogar.esCreador`.

## Identidad sin correo obligatorio
PocketBase no tiene login anónimo. Cada dispositivo crea un usuario con credenciales aleatorias
(`<uuid>@device.invalid` + contraseña aleatoria) guardadas en almacenamiento seguro. El correo real
es opcional y solo sirve para recuperar la cuenta vía el relay SMTP. Se pide un alias visible.

## Colecciones PocketBase
| Colección | Campos principales |
|---|---|
| `users` (auth) | alias |
| `hogares` | name, emoji, owner→users, invite_code (texto aleatorio, regenerable), ntfy_topic (aleatorio largo) |
| `miembros` | hogar→hogares, user→users, alias, rol (`owner`/`member`) |
| `items` | hogar, name, barcode, cold, urg, done, store_id, price, added_by→users, client_updated, deleted |
| `ofertas` | hogar, key, name, chain, price, until |
| `rutas` | hogar, chain, user→users, day («voy yo a este súper») |

Reglas de acceso (ejemplo para `items`; las demás igual con `hogar`):
```
listRule/viewRule:   @request.auth.id != "" && hogar.miembros_via_hogar.user ?= @request.auth.id
createRule/updateRule: lo mismo
deleteRule: null   // se borra con el campo deleted (tombstone) para que sincronice
```
Unirse por código: endpoint propio (hook JS) `POST /api/mm/join {code}` que valida el código y crea la
fila de `miembros`; no se deja crear `miembros` directamente. Límite de 3 hogares por usuario validado en ese hook.

## Sincronización en la app
- Interfaz `ListRepository` con dos implementaciones: `LocalRepository` (actual) y `PocketBaseRepository`.
- Suscripción SSE (`/api/realtime`) a `items`, `ofertas`, `rutas` del hogar activo; al volver la conexión,
  se vacía la cola local y se hace un `getList` filtrado por `client_updated > último_sync`.
- Sin SDK obligatorio: `http` + SSE (ya es dependencia); el SDK `pocketbase` de Dart es opcional.

## Avisos con ntfy
- Un hook de PocketBase publica en `https://<ntfy>/<ntfy_topic>` cuando se crea un item urgente o
  alguien marca comprado lo último de una tienda.
- El topic es largo y aleatorio por hogar; además se recomienda ACL en ntfy (usuario/token por hogar).
- iOS recibe ntfy vía APNs relay de ntfy.sh (`upstream-base-url`) o la app ntfy; decidir al montar el servidor.

## Privacidad y publicación
- No se guardan ubicación ni temporizador en el servidor. Solo contenido de la lista.
- Política de privacidad y borrado de cuenta dentro de la app (requisito de App Store).
- El servidor es configurable (`URL` en Ajustes) para que terceros usen el suyo con el mismo esquema
  (migración PocketBase incluida en `server/pb_migrations`, pendiente).

## Fases
1. ✅ Listas locales múltiples.
2. ✅ Esquema PocketBase + migraciones + hooks (`server/`), desplegado en el servidor propio y probado (26/26 permisos).
3. `PocketBaseRepository`, cola offline, tiempo real, unirse por código.
4. «Voy yo a este súper», autoría visible.
5. ntfy y recuperación por correo.

# Servidor MultiMarket (PocketBase)

> **Configuración privada:** servidor, usuario SSH y correo del administrador viven FUERA del repositorio, en
> `../MultiMarket-privado/config.env` (o la ruta de `$MM_PRIVATE`). Los scripts de esta carpeta la cargan con
> `lib_config.sh`. Variables: `MM_SSH`, `MM_REMOTE_DIR`, `MM_CONTAINER`, `MM_LAN_URL`, `MM_PUBLIC_URL`, `MM_ADMIN_EMAIL`.

Infraestructura propia (ver el README privado del servidor). Aquí solo viven las migraciones y hooks de MultiMarket.

- `pb_migrations/1790000000_multimarket_schema.js` — colecciones `hogares`, `miembros`, `items`, `ofertas`, `rutas` y campo `alias` en `users`.
- `pb_hooks/multimarket.pb.js` — límite de 3 listas, código de invitación, `POST /api/mm/join`,
  `POST /api/mm/hogares/{id}/invitacion` (regenerar), `POST /api/mm/hogares/{id}/transferir`, salida ordenada del creador.
- `tests/integration_test.py` — prueba de extremo a extremo (26 comprobaciones de permisos). **No necesita
  credenciales de admin**: crea 3 usuarios temporales y cada uno borra lo suyo. Respeta el rate limiting
  (alta de usuarios 5/min por IP: no lanzarla más de una vez por minuto). `MM_URL` elige el servidor
  (por defecto el servicio público).

## Administración
El superusuario usa contraseña + OTP por correo: los scripts ya no pueden entrar solos.
Para tareas de admin usar el panel o la CLI del contenedor
(`docker exec multimarket-pb /usr/local/bin/pocketbase ... --dir=/pb_data`).
Backups: panel → *Settings → Backups* (o `POST /api/backups` con sesión de superusuario).

## Desplegar
```bash
# 1) backup (panel: Settings → Backups) o por API; 2) copiar; 3) reiniciar solo multimarket-pb
rsync -av server/pb_migrations/ $MM_SSH:$MM_REMOTE_DIR/pb_migrations/
rsync -av server/pb_hooks/      $MM_SSH:$MM_REMOTE_DIR/pb_hooks/
ssh $MM_SSH "cd $MM_REMOTE_DIR && docker compose restart && docker logs --tail 20 $MM_CONTAINER"
MM_URL=https://tu-servidor python3 server/tests/integration_test.py
```
Notas de PocketBase 0.40: en migraciones usar `fields.add(new TextField({...}))` (no `push` de objeto planos);
las reglas que usan una relación inversa (`miembros_via_hogar`) se fijan **después** de crear `miembros`.

## Fotos de la comunidad y moderación por lotes
- Colección `fotos` (migraciones 0002 y 0003, hook `fotos.pb.js`). Cualquier usuario con sesión puede subir una foto
  con `consent=true`; entra siempre como `pending` y a su nombre. **Solo las `approved` son públicas**
  (`GET /api/collections/fotos/records?filter=key='<código>' && status='approved'`, sin sesión).
  El autor ve y puede retirar las suyas; no puede aprobarlas ni editarlas. Máx. 3 MB, JPEG/PNG/WebP, 30 pendientes por usuario.
- **Moderar por lotes** (panel `/_/` → colección `fotos`): filtrar `status = "pending"`, revisar las miniaturas y
  cambiar `status` a `approved` o `rejected` (con un motivo en `note`). El panel permite edición múltiple. Pendiente de decidir
  un criterio (p. ej. aprobar solo fotos frontales sin personas/datos personales) y una rutina periódica.
- La app enlaza primero la foto de Open Food Facts; si no hay, busca una aprobada aquí; si tampoco, se usa la que el usuario haga en local.
- Pruebas: `python3 server/tests/fotos_test.py` (13 comprobaciones; sin credenciales de admin; ≤ 1 vez por minuto).

## Gotcha de migraciones (PocketBase 0.40)
Crear una colección con campos tipados y reglas que los usan en una sola llamada puede dejarla vacía y sin reglas.
Hacerlo en dos pasos: crear/guardar los campos y después fijar las reglas (ver `1790000003_fotos_esquema.js`).

## Copias de seguridad
- **Automáticas:** cada día a las 04:00 PocketBase crea una copia en `pb_data/backups/` y conserva las 7 últimas
  (migración `1790000007_backups_diarios.js`; se ve en el panel → Settings → Backups).
- **Fuera del servidor:** `server/backup_pull.sh` trae a tu Mac la copia más reciente a `~/Backups/multimarket`
  (conserva 14). Se puede programar con launchd/cron. Lee los zip con `sudo` por SSH.
- **Restaurar:** panel → Settings → Backups → Restore, o parar el contenedor y sustituir `pb_data` por el contenido del zip.
- Antes de cada migración manual se copia `data.db` a `backups/pre_*.data.db` (no los toca la rotación automática).

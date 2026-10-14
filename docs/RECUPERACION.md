# Recuperación ante desastres

Qué hacer si el servidor de MultiMarket se pierde o se corrompe. Los datos privados (host, accesos) viven en la
infraestructura privada y no en este repositorio.

## Qué copias existen
| Dónde | Qué | Frecuencia / retención |
|---|---|---|
| Servidor (`pb_data/backups`) | `@auto_pb_backup_multi_market_AAAAMMDD040000.zip` (datos, fotos y ajustes) | diaria 04:00, 7 copias |
| NAS con RAID1 | los mismos `.zip`, descargados por el NAS | diaria 07:15, 30 días |
| Equipo del propietario | `server/backup_pull.sh` baja la última a `~/Backups/multimarket` | a mano |

El código (hooks, migraciones, página de moderación y web) está en GitHub: `8aws/MultiMarket`.

## Escenarios
**A. Los datos se corrompen pero el servidor funciona**
1. Moderación → pestaña **Copias** → **Restaurar** en la copia del servidor que quieras (la más reciente buena).
2. Antes se guarda sola una copia del estado actual (`pre_restauracion_….zip`); el servidor se reinicia.

**B. Hay que reinstalar los contenedores (o cambiar de máquina/discos)**
1. Desplegar los contenedores de MultiMarket con el `docker-compose.yml` privado y volumen `pb_data` vacío.
2. Copiar `server/pb_migrations`, `server/pb_hooks` (**conservando `zz_infra_*` de la infraestructura**) y desplegar la web con
   `server/deploy_web.sh`. Reiniciar el contenedor.
3. PocketBase, al arrancar vacío, ofrece crear el **primer superusuario** (enlace en los registros del contenedor, `/_/#/pbinstal/…`).
   Crear uno temporal.
4. Bajar del NAS la copia más reciente (`*.zip`) a tu ordenador.
5. Abrir `…/moderacion/`, entrar con el superusuario temporal → **Copias** → elegir el `.zip` → escribir `RESTAURAR`.
   (Alternativa: panel `/_/` → Ajustes → Copias de seguridad → *Subir* y *Restaurar*.)
6. El servidor se reinicia con los datos de la copia, **incluidos los superusuarios y sus ajustes**; el superusuario temporal
   desaparece. Entrar con tu cuenta habitual.
7. Comprobar: `/api/health`, una sincronización desde el iPhone, estado de copias en moderación.
8. Reactivar/verificar el backup diario (Ajustes → Copias) y el pull del NAS.

## Notas
- Las migraciones pendientes se aplican solas al arrancar tras restaurar una copia antigua.
- Los dispositivos conservan su sesión: el token va firmado con una clave por usuario que también está en la copia.
- Se pierde lo creado **después** de la copia elegida (por eso la diaria y el NAS a los 30 días).
- No restaurar por encima de producción sin la copia previa: la página la hace sola, pero conviene comprobar que existe.
- La subida a través del proxy inverso puede tener límite de tamaño; hoy las copias pesan ~2 MB.

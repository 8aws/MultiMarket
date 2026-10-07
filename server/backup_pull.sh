#!/usr/bin/env bash
# Trae a este Mac la copia de seguridad más reciente de PocketBase (la hace el propio servidor cada día a las 04:00).
# Conserva las 14 últimas en ~/Backups/multimarket. Así hay una copia FUERA del servidor.
# Uso: server/backup_pull.sh   (puede ir en un cron/launchd del Mac)
set -euo pipefail
. "$(dirname "$0")/lib_config.sh"
DEST="${MM_BACKUP_DIR:-$HOME/Backups/multimarket}"
HOST="$MM_SSH"
REMOTE="$MM_REMOTE_DIR/pb_data/backups"
mkdir -p "$DEST"
ULTIMA=$(ssh -o BatchMode=yes "$HOST" "sudo ls -1t $REMOTE/*.zip 2>/dev/null | head -1")
[ -n "$ULTIMA" ] || { echo "No hay copias en el servidor todavía"; exit 1; }
NOMBRE=$(basename "$ULTIMA")
if [ -f "$DEST/$NOMBRE" ]; then echo "Ya la tenías: $NOMBRE"; exit 0; fi
ssh -o BatchMode=yes "$HOST" "sudo cat $ULTIMA" > "$DEST/$NOMBRE.tmp"
mv "$DEST/$NOMBRE.tmp" "$DEST/$NOMBRE"
ls -1t "$DEST"/*.zip | tail -n +15 | xargs -I{} rm -f {}
echo "Guardada: $DEST/$NOMBRE ($(du -h "$DEST/$NOMBRE" | cut -f1))"

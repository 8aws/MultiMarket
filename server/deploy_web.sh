#!/usr/bin/env bash
# Despliega la web de Flutter + las páginas estáticas (moderación y privacidad) en el servidor.
# (rsync --delete borraría esas carpetas si no se copian dentro del build antes.)
set -euo pipefail
cd "$(dirname "$0")/.."
. server/lib_config.sh
flutter build web --release
for d in moderacion privacidad privacy info; do
  mkdir -p "build/web/$d"; cp server/$d/* "build/web/$d/"
done
rsync -av --delete build/web/ "$MM_SSH:$MM_REMOTE_DIR/pb_public/"

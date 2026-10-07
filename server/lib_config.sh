# Carga la configuración privada (fuera del repo): ../MultiMarket-privado/config.env o $MM_PRIVATE/config.env.
# Variables: MM_SSH, MM_LAN_URL, MM_PUBLIC_URL, MM_REMOTE_DIR, MM_CONTAINER, MM_ADMIN_EMAIL.
_src="${BASH_SOURCE[0]:-$0}"
_dir="$(cd "$(dirname "$_src")/.." && pwd)"
_priv="${MM_PRIVATE:-$_dir/../MultiMarket-privado}"
if [ -f "$_priv/config.env" ]; then set -a; . "$_priv/config.env"; set +a; fi
: "${MM_SSH:?Falta MM_SSH (usuario@servidor). Crea ../MultiMarket-privado/config.env o exporta la variable}"
: "${MM_REMOTE_DIR:=/opt/multimarket}"
: "${MM_CONTAINER:=multimarket-pb}"

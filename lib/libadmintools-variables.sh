# shellcheck shell=sh
# shellcheck disable=SC2034


DYSTOPIAN_USER="root"
DC_POS_ARGS=

DYSTOPIAN_CFGDIR="/etc/dystopian"
DYSTOPIAN_DATADIR="/var/lib/dystopian"
DYSTOPIAN_LIBDIR="/usr/lib/dystopian"

# HOSTS
DH_DIR="$DYSTOPIAN_CFGDIR/hosts"
DH_DB="$DH_DIR/data.json"


# AURTOOLS
DA_DIR="$DYSTOPIAN_CFGDIR/dystopian-aurtool"
DA_DB="$DA_DIR/aurtool-db.json"
GH_API_BASE="https://api.github.com/repos"
DA_BASE_URL="https://github.com/Dystopian-Project"

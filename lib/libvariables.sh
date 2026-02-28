# shellcheck shell=sh
# shellcheck disable=SC2034


_APP_NAME="${_APP_NAME:-${0##*dystopian-}}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

DC_POS_ARGS=

DYSTOPIAN_CFGDIR="/etc/dystopia/$_APP_NAME"
DYSTOPIAN_LIBDIR="/usr/lib/dystopian"
DYSTOPIAN_DATADIR="/var/lib/dystopian/$_APP_NAME"
DYSTOPIAN_LOGDIR="/var/log/dystopian/$_APP_NAME"
DYSTOPIAN_DB="$DYSTOPIAN_DATADIR/data.json"
DYSTOPIAN_CFG="$DYSTOPIAN_CFGDIR/default.conf"
DYSTOPIAN_LOGFILE="$DYSTOPIAN_LOGDIR/$(date +'%Y-%m-%d_%H-%M-%S').log"

DEBUG="${DEBUG:-0}"
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"

DYSTOPIAN_USER="$([ -n "$SUDO_USER" ] && echo "$SUDO_USER" || echo "root")"

LOG_LIB_FILE="$DYSTOPIAN_LIBDIR/libapplog.sh"
HELPER_LIB_FILE="$DYSTOPIAN_LIBDIR/libhelper.sh"

[ -f "$LOG_LIB_FILE" ] || LOG_LIB_FILE="$SCRIPT_DIR/../../lib/libapplog.sh"
[ -f "$HELPER_LIB_FILE" ] || HELPER_LIB_FILE="$SCRIPT_DIR/../../lib/libhelper.sh"

# Source library files
# shellcheck source=../dystopian-libs/lib/libapplog.sh
[ -f "$LOG_LIB_FILE" ] && . "$LOG_LIB_FILE"
# shellcheck source=../dystopian-libs/lib/libhelper.sh
[ -f "$HELPER_LIB_FILE" ] && . "$HELPER_LIB_FILE"


if [ "$_APP_NAME" = "crypto" ]; then
  SSL_LIB_FILE="$DYSTOPIAN_LIBDIR/libssl.sh"
  [ -f "$SSL_LIB_FILE" ] || SSL_LIB_FILE="$SCRIPT_DIR/../../lib/libssl.sh"
  # shellcheck source=../dystopian-libs/lib/libssl.sh
  [ -f "$SSL_LIB_FILE" ] && . "$SSL_LIB_FILE"

  GPG_LIB_FILE="$DYSTOPIAN_LIBDIR/libgpg.sh"
  [ -f "$GPG_LIB_FILE" ] || GPG_LIB_FILE="$SCRIPT_DIR/../../lib/libgpg.sh"
  # shellcheck source=../dystopian-libs/lib/libgpg.sh
  [ -f "$GPG_LIB_FILE" ] && . "$GPG_LIB_FILE"

  FRITZ_LIB_FILE="$DYSTOPIAN_LIBDIR/libfritztls.sh"
  [ -f "$FRITZ_LIB_FILE" ] || FRITZ_LIB_FILE="$SCRIPT_DIR/../../lib/libfritztls.sh"
  # shellcheck source=../dystopian-libs/lib/libfritztls.sh
  [ -f "$FRITZ_LIB_FILE" ] && . "$FRITZ_LIB_FILE"

  TPM2_LIB_FILE="$DYSTOPIAN_LIBDIR/libtpm2.sh"
  [ -f "$TPM2_LIB_FILE" ] || TPM2_LIB_FILE="$SCRIPT_DIR/../../lib/libtpm2.sh"
  # shellcheck source=../dystopian-libs/lib/libtpm2.sh
  [ -f "$TPM2_LIB_FILE" ] && . "$TPM2_LIB_FILE"

  USB_LIB_FILE="$DYSTOPIAN_LIBDIR/libexttoken.sh"
  [ -f "$USB_LIB_FILE" ] || USB_LIB_FILE="$SCRIPT_DIR/../../lib/libexttoken.sh"
  # shellcheck source=../dystopian-libs/lib/libexttoken.sh
  [ -f "$USB_LIB_FILE" ] && . "$USB_LIB_FILE"

  DCS_DB_LIB_FILE="$DYSTOPIAN_LIBDIR/libssl-db.sh"
  [ -f "$DCS_DB_LIB_FILE" ] || DCS_DB_LIB_FILE="$SCRIPT_DIR/../../lib/libssl-db.sh"
  # shellcheck source=../dystopian-libs/lib/libssl-db.sh
  [ -f "$DCS_DB_LIB_FILE" ] && . "$DCS_DB_LIB_FILE"

  DCG_DB_LIB_FILE="$DYSTOPIAN_LIBDIR/libgpg-db.sh"
  [ -f "$DCG_DB_LIB_FILE" ] || DCG_DB_LIB_FILE="$SCRIPT_DIR/../../lib/libgpg-db.sh"
  # shellcheck source=../dystopian-libs/lib/libgpg-db.sh
  [ -f "$DCG_DB_LIB_FILE" ] && . "$DCG_DB_LIB_FILE"

  DC_CFG_FILE="$DYSTOPIAN_CFGDIR/crypto.conf"
  [ -f "$DC_CFG_FILE" ] || DC_CFG_FILE="$SCRIPT_DIR/../../conf/crypto.conf"
  # shellcheck source=conf/crypto.conf
  [ -f "$DC_CFG_FILE" ] && . "$DC_CFG_FILE"

fi


DC_CA="$DYSTOPIAN_DATADIR/ca"
DC_CERT="$DYSTOPIAN_DATADIR/cert"
DC_KEY="$DYSTOPIAN_DATADIR/cert/private"
DC_CRL="$DYSTOPIAN_DATADIR/crl"
DC_CAKEY="$DYSTOPIAN_DATADIR/ca/private"
DC_OLD="$DYSTOPIAN_DATADIR/old"
DC_GNUPG="$DYSTOPIAN_DATADIR/gnupg"
DC_DB="$DYSTOPIAN_DATADIR/data.json"
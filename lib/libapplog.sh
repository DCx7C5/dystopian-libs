# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2181
_BOLD="\033[1m"
_COL_ERROR="\033[31m"
_COL_WARNING="\033[33m"
_COL_NOTE="\033[34m"
_COL_INFO="\033[36m"
_COL_DEBUG="\033[37m"
_COL_SUCCESS="\033[32m"
_COL_SPINNER="\033[32m"
_COL_YELLOW="\033[33m"
_RESET="\033[0m"

_spin="\u280B\u2819\u2839\u2838\u283C\u2834\u2826\u2827\u2807\u280F"

DEBUG_LEVEL="${DEBUG_LEVEL:-5}"
FILE_LOGGER="${FILE_LOGGER:-0}"
JSON_LOGGER="${JSON_LOGGER:-0}"

[ ! -d "$DYSTOPIAN_LOGDIR" ] && mkdir -p "$DYSTOPIAN_LOGDIR" 2>/dev/null
[ ! -f "$DYSTOPIAN_LOGFILE" ] && touch "$DYSTOPIAN_LOGFILE" 2>/dev/null
[ "$DEBUG" -eq 1 ] && DEBUG_LEVEL=7
[ "$VERBOSE" -eq 1 ] && DEBUG_LEVEL=6
[ "$QUIET" -eq 1 ] && DEBUG_LEVEL=0


_compose_line_json_out() {
  printf '{"timestamp":"%s","level":"%s","func_name":"%s","msg":"%s","error":"%s","service":"%s"}\n' "$1" "$2" "$3" "$4" "$5" "$_APP_NAME"
}

_compose_line_logfmt_out() {
  printf "ts=%s level=%s func_name=%s msg=%s error=%s service=%s\n" "$1" "$2" "$3" "$4" "$5" "$_APP_NAME"
}

# 1: prefix, 2: color, 3: level, 4: msg, 5: func_name
# shellcheck disable=SC2086
_compose_line_std() {
  _lvl="$3"
  _pfx="${_BOLD}${2}${1}${_RESET}"
  _msg="${_BOLD}${_COL_DEBUG}${4}${_RESET}"

  if [ "$DEBUG" -eq 1 ] || [ "$VERBOSE" -eq 1 ]; then
    _wsc=$((8 - ${#_lvl}))
    _func="${5:+"${_BOLD}${_COL_YELLOW}${5}${_RESET}"}"
    _lvl="${_BOLD}${2}$(printf "%*s" $_wsc | tr ' ' ' ')${_lvl}${_RESET}"
    { [ "$DEBUG" -eq 1 ] && [ -n "$_func" ];} && _lvl="${_lvl} ($_func)${_RESET}" || _lvl="${_lvl}${_BOLD}${_COL_DEBUG}:${_RESET}"
    _pfx="${_pfx}${_lvl}"
  fi

  printf "%s %s" "$_pfx" "$_msg"
}


_log_to_file() {
  if [ "$JSON_LOGGER" -eq 1 ]; then
    _compose_line_json_out "$1" "$2" "$3" "$4" "$5" >> "$_LOG_FILE"
  else
    _compose_line_logfmt_out "$1" "$2" "$3" "$4" "$5" >> "$_LOG_FILE"
  fi
}

# 1: prefix, 2: color, 3: level, 4: func_name, 5: crnl, 6: msg, 7: error
_log_to_stdout() {
  _out="$(_compose_line_std "$1" "$2" "$3" "$6" "$4")"
  printf "%b%b" "$_out" "$5"
}

# 1: prefix, 2: color, 3: level, 4: func_name, 5: crnl, 6: msg, 7: error
_log_to_stderr() {
  _out="$(_compose_line_std "$1" "$2" "$3" "$6" "$4")"
  _err="$(_compose_line_std "$1" "$2" "$3" "$7" "$4")"
  printf "%b\n%b%b" "$_out" "$_err" "$5" >&2
}


_log_message() {
  _date=$(date +"%Y-%m-%dT%H:%M:%S$(date +%z | sed 's/\(..\)$/:\1/')")
  _severity="${1:-note}"
  _msg="${2:-}"
  _crnl="${3:-0}"
  _error="${4:-}"

  case "$3" in
    0) _crnl='\n';;
    1) _crnl='\r';;
    2|*) _crnl='';;
  esac

  case "$_severity" in
    error)    _lvl=ERROR;   _pfx='>';      _col="$_COL_ERROR";   _sev=3;;
    warning)  _lvl=WARNING; _pfx='>';      _col="$_COL_WARNING"; _sev=4;;
    note)     _lvl=NOTE;    _pfx='>';      _col="$_COL_NOTE";    _sev=5;;
    info)     _lvl=INFO;    _pfx='>';      _col="$_COL_INFO";    _sev=6;;
    debug)    _lvl=DEBUG;   _pfx='>';      _col="$_COL_DEBUG";   _sev=7;;
    success)  _lvl=NOTE;    _pfx='>>>';    _col="$_COL_SUCCESS"; _sev=5;;
    isuccess) _lvl=INFO;    _pfx='>';      _col="$_COL_SUCCESS"; _sev=6;;
    spinner)  _lvl=NOTE;    _pfx="$_spin"; _col="$_COL_SPINNER"; _sev=5;;
    *)        _lvl=NOTE;    _pfx='>';      _col="$_COL_NOTE";    _sev=5;;
  esac

  if [ "$FILE_LOGGER" -eq 1 ]; then
    _log_to_file "$_date" "$_lvl" "$_msg" "$_error" &
  fi

  if [ "$QUIET" -ne 1 ] && [ "$_sev" -le "$DEBUG_LEVEL" ]; then
    if [ -n "$_error" ]; then
      _log_to_stderr "$_pfx" "$_col" "$_lvl" "$_crnl" "$_msg" "$_error"
    else
      _log_to_stdout "$_pfx" "$_col" "$_lvl" "$_crnl" "$_msg"
    fi
  fi

}


echoi() {
  if [ "$QUIET" -ne 1 ]; then
    if [ "$DEBUG" -eq 1 ]; then istr="    INFO:"; else istr=""; fi
    printf "\033[1;34m>%s\033[1;37m %s\033[0m\n" "$istr" "$1"
  fi
}


echov() {
  if [ "$VERBOSE" -eq 1 ]; then
    if [ "$DEBUG" -eq 1 ]; then istr="    INFO:"; else istr=""; fi
    printf "\033[1;36m>%s\033[1;37m %s\033[0m\n" "$istr" "$1"
  fi
}


echod() {
  [ "$DEBUG" -eq 1 ] && printf "\033[1;37m>   DEBUG:\033[0m %s\n" "$1"
}


echow() {
  wstr=""
  if [ "$QUIET" -ne 1 ]; then
    [ "$DEBUG" -eq 1 ] && wstr=" WARNING:"
    printf "\033[1;33m>%s\033[1;37m %s\033[0m" "$wstr" "$1" >&2 2>/dev/null
    [ -z "$2" ] && [ "$2" != "nonl" ] && printf "\n" >&2
    [ "$2" = '\r' ] && printf "\r" >&2
  fi
}


echowv() {
  [ "$VERBOSE" -ne 1 ] && return 0
  echow "$1"
}


echoe() {
  printf "\033[1;31m>   ERROR:\033[1;37m %s\033[0m\n" "$1" >&2
}


echos() {
  istr=""
  if [ "$QUIET" -ne 1 ]; then
    [ "$DEBUG" -eq 1 ] && istr="  INFO:"
    printf "\033[1;32m>>>%s\033[1;37m %s\033[0m\n" "$istr" "$1"
  fi
}


echosv() {
  istr=""
  if [ "$VERBOSE" -eq 1 ]; then
    [ "$DEBUG" -eq 1 ] && istr="    INFO:"
    printf "\033[1;32m>%s\033[1;37m %s\033[0m\n" "$istr" "$1"
  fi
}


askyesno() {
  default="$2"
  case "$default" in
  y|Y|yes|Yes|YES)
    question=$(printf "%s [Y/n]: " "$1")
    default_return=0
    ;;
  n|N|no|No|NO)
    question=$(printf "%s [y/N]: " "$1")
    default_return=1
    ;;
  *)
    question=$(printf "%s [y/N]: " "$1")
    default_return=1
    ;;
  esac
  while true; do
    log_warn "$question" "$0" 2
    read -r yesno < /dev/tty
    case "$yesno" in
      y|Y|j|J|yes|Yes|YES) return 0;;
      n|N|no|NO|No) return 1;;
      "") return $default_return;;
      * ) ;;
    esac
  done
}


prompt_passphrase() {
  secret=
  oldtty=$(stty -F /dev/tty -g 2>/dev/null || echo '')
  trap 'stty -F /dev/tty "$oldtty" 2>/dev/null || stty -F /dev/tty sane 2>/dev/null' INT TERM HUP EXIT
  stty -F /dev/tty -echo 2>/dev/null
  if [ "$1" = true ]; then
    echow "Enter pass phrase for $2: " "nonl"
  else
    echow "Verifying - Enter pass phrase for $2: " "nonl"
  fi
  IFS= read -r secret </dev/tty
  printf "\n" >&2
  printf '%s' "$secret"
  stty -F /dev/tty "$oldtty" 2>/dev/null || stty -F /dev/tty sane 2>/dev/null
  unset secret
}

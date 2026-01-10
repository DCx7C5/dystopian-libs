# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2034
# shellcheck disable=SC2181

umask 077


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
    if [ "$2" = 'tty' ]; then
      printf "\033[1;33m>%s\033[1;37m %s\033[0m" "$wstr" "$1" >/dev/tty 2>/dev/null
    else
      printf "\033[1;33m>%s\033[1;37m %s\033[0m" "$wstr" "$1" >&2
    fi
    [ -z "$2" ] && printf "\n" >&2
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
    echow "$question" 1
    read -r yesno < /dev/tty
    case "$yesno" in
      y|Y|j|J|yes|Yes|YES) return 0;;
      n|N|no|NO|No) return 1;;
      "") return $default_return;;
      * ) ;;
    esac
  done
}

askpassword() {
  PASSPHRASE=
  PASSPHRASE=$(
    exec </dev/tty
    tty_settings=$(stty -g)
    trap 'stty "$tty_settings"' EXIT INT TERM
    stty -echo
    echow "Enter passphrase: " >/dev/tty
    IFS= read -r password
    echo > /dev/tty
    printf '%s\n' "$password"
  )
  unset PASSPHRASE
}

is_ip() {
  ip="$1"
  if echo "$ip" | grep -E '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' >/dev/null 2>&1; then
    return 0
  elif echo "$ip" | grep -E '^([0-9a-fA-F]{1,4}:){0,7}[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,7}$|^::1$' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

shorthelp() {
  echo ""
  help | sed -n "/^  $1/,/^$/p"
}

sslhelp() {
  echo ""
  help | sed -n "/^SSL Com/,/^GPG/{/^GPG/d; p}"
}

gpghelp() {
  echo ""
  help | sed -n "/^GPG Com/,/^Main/{/^Main/d; p}"
}

reset_dystopian_crypto() {
  ssl="${1:-false}"
  gpg="${2:-false}"
  if askyesno "Are you sure you want to reset the config and keys?" "n";then
    if askyesno "Do you want to backup the directory first?" "y"; then
      cp -rf "$DC_CFGDIR" "${DC_CFGDIR}.bkp" 2>/dev/null || {
          echoe "Problem backing up keys and config"
          exit 1
      }
      echos "Backup successful @ /etc/dystopian-crypto.bkp"
    fi
    { [ "$ssl" = true ] && [ "$gpg" = true ]; } && echow "--ssl or --gpg flag not set."
    if [ -n "$ssl" ] && [ "$ssl" = "true" ]; then
      if askyesno "Last WARNING! Answering yes will delete everything SSL related in $DC_CFGDIR & $DC_DB" "N"; then
        rm -rf -- "${DC_CA}" "${DC_CERT}" "${DC_CRL}" 2>/dev/null || {
            echoe "Problem resetting dystopian-crypto ssl"
            exit 1
        }
        mkdir -p -- "$DC_CAKEY" "$DC_KEY" "$DC_CRL" || {
            echoe "Problem creating ssl directories"
            exit 1
        }
        set_permissions_and_owner "$DC_CFGDIR" 750
        set_permissions_and_owner "$DC_KEY" 700
        set_permissions_and_owner "$DC_CAKEY" 700
        for i in $(get_all_indices); do
          manage_truststore "$i" "uninstall"
        done
        reset_ssl_index
        echos "Reset of dystopian-crypto SSL successful"
      else
        echoi "Exiting dystopian-crypto. No harm was done."
        exit 0
      fi
    fi
    if [ -n "$gpg" ] && [ "$gpg" = "true" ]; then
      if askyesno "Last WARNING! Answering yes will delete everything GPG related in $DC_GNUPG & $DC_DB" "N"; then
        rm -rf -- "${DC_GNUPG}" 2>/dev/null || {
          echoe "Problem resetting dystopian-crypto GPG"
          exit 1
        }
        mkdir -p -- "$DC_GNUPG" || {
          echoe "Failed creating new GPG home directory"
          exit 1
        }
        set_permissions_and_owner "$DC_GNUPG" 700
        reset_gpg_index
        echos "Reset of dystopian-crypto GPG successful"
      else
        echoi "Exiting dystopian-crypto. No harm was done."
        exit 0
      fi
    fi

  else
    echoi "Exiting dystopian-crypto. No harm was done."
    exit 0
  fi
}

# Maintenance and utility functions
show_index() {
    show_keys="${1:-false}"
    show_ca="${2:-false}"
    show_json="${3:-false}"

    if [ "$show_json" = "true" ]; then
        jq '.' -- "$DC_DB"
        return 0
    fi

    echoi "dystopian-crypto Index Summary"
    echo "  =============================="
    echo ""

    # Show default CA
    if has_defaultRootCA; then
      default_root_ca="$(get_value_from_ca_index "$(get_defaultRootCA)" "name")"
      echoi "Default RootCA: $default_root_ca"
    fi

    if has_defaultCA; then
      default_ca="$(get_value_from_ca_index "$(get_defaultCA)" "name")"
      echoi "Default CA: $default_ca"
    fi

    if [ "$show_ca" = "true" ] || [ "$show_keys" = "false" ]; then
        echo ""
        echoi "Certificate Authorities:"
        # Show root CAs
        echoi "  Root CAs:"
        jq -r '.ssl.rootCAs | to_entries[] | "    - " + .key' -- "$DC_DB" 2>/dev/null || echo "  None"

        # Show intermediate CAs
        echoi "  Intermediate CAs:"
        jq -r '.ssl.intermediateCAs | to_entries[] | "    - " + .key' -- "$DC_DB" 2>/dev/null || echo "  None"
        echo ""
    fi

    if [ "$show_keys" = "true" ] || [ "$show_ca" = "false" ]; then
        echoi "Keys and Certificates:"
        echo "  ----------------------"
        key_count=$(jq -r '.ssl.certs | length' -- "$DC_DB")

        if [ "$VERBOSE" -eq 1 ]; then
            jq -r '.ssl.certs | to_entries[] | "  - " + .key + ": " + (.value | to_entries | map(.key + "=" + .value) | join(", "))' -- "$DC_DB" 2>/dev/null
        fi
        echo ""
        echos "Total key entries: $key_count"
    fi
}


cleanup_dcrypto_files() {
  cleanup_index="$1"
  cleanup_orphaned="${2:-false}"
  cleanup_backups="${3:-false}"
  cleanup_non_ca_keys="${4:-false}"
  cleanup_dry_run="${5:-false}"
  keep_backups="${6:-2}"  # Number of recent backup CSRs to keep

  echod "Starting cleanup_dcrypto_files with parameters:"
  echod "        cleanup_index: $cleanup_index"
  echod "     cleanup_orphaned: $cleanup_orphaned"
  echod "      cleanup_backups: $cleanup_backups"
  echod "  cleanup_non_ca_keys: $cleanup_non_ca_keys"
  echod "      cleanup_dry_run: $cleanup_dry_run"
  echod "         keep_backups: $keep_backups"
  echod "            DC_CFGDIR: $DC_CFGDIR"
  echod "                DC_DB: $DC_DB"

  echoi "dystopian-crypto Cleanup${cleanup_dry_run:+$([ "$cleanup_dry_run" = "true" ] && echo "DRY RUN")}"
  echoi "=============="

  # Clean specific index
  if [ -n "$cleanup_index" ]; then
    echoi "Cleaning up specific index: $cleanup_index"
    if ! has_index "$cleanup_index"; then
      echoe "Index $cleanup_index does not exist in $DC_DB"
      return 1
    fi
    if [ "$cleanup_dry_run" != "true" ]; then
      manage_truststore "$cleanup_index" "uninstall"
      delete_ssl_index "$cleanup_index" || {
          echoe "Failed to clean index $cleanup_index"
          return 1
      }
      echos "Index $cleanup_index cleaned successfully"
    else
      echov "Dry run: Would clean index $cleanup_index"
    fi
    return 0
  fi

  # Clean orphaned files
  if [ "$cleanup_orphaned" = "true" ]; then
    echoi "Finding orphaned files..."
    tmpfile_orphaned=$(mktemp) || { echoe "Failed to create temporary import_file for orphaned files"; return 1; }
    find "$DC_CFGDIR" -type f \( -name "*.pem" -o -name "*.csr" -o -name "*.conf" -o -name "*.salt" -o -name "*.srl" \) > "$tmpfile_orphaned"
    found_orphaned=false
    while read -r import_file; do
      file_path="$(realpath "$import_file")"
      file_name="$(basename "$import_file")"
      file_ext="${file_name#*.*.*.}"
      [ -z "$file_ext" ] && file_ext="${file_name#*.*.}"
      [ -z "$file_ext" ] && file_ext="${file_name#*.}"
      [ -z "$file_ext" ] && return 1
      echod "Checking if import_file is orphaned: $file_path"
      case "$file_ext" in
        csr) k="csr";;
        conf|cfg) k="cfg";;
        salt) k="salt";;
        pem)
          case "$file_name" in
            ^ca-key.*|^key.*) k="key";;
            ^ca.*|^cert.*) k="cert";;
            ^fullchain) k="fullchain";;
          esac
          ;;
      esac
      idx="$(find_index_by_key_value "$k" "$file_path")"
      if [ -z "$idx" ] || [ "$idx" = "" ]; then
        found_orphaned=true
        echoi "Orphaned file: $file_path"
        if [ "$cleanup_dry_run" != "true" ]; then
            rm -f -- "$file_path" || {
                echoe "Failed to remove orphaned import_file: $file_path"
                break
            }
            echos "Removed orphaned import_file: $file_path"
        else
            echov "Dry run: Would remove orphaned import_file: $file_path"
        fi
      else
        echoe "Found"
      fi
    done < "$tmpfile_orphaned"
    rm -f -- "$tmpfile_orphaned"
    if [ "$found_orphaned" = "false" ]; then
        echoi "No orphaned files found"
    fi
    echos "Orphaned import_file cleanup completed"
  fi

  # Clean backup files
  if [ "$cleanup_backups" = "true" ]; then
    echoi "Cleaning up backup files..."
    tmpfile_backups=$(mktemp) || { echoe "Failed to create temporary import_file for backup files"; return 1; }
    find "$DC_CFGDIR" -type f \( -name "*bkp*" -o -name "cert.[0-9]*.csr" \) > "$tmpfile_backups"
    found_backups=false
    while IFS= read -r backup_file < "$tmpfile_backups"; do
      found_backups=true
      backup_file_path="$(realpath "$backup_file")"
      # Check if import_file is a csrbkp in index.json
      index=$(jq -r --arg path "$backup_file_path" '.ssl.keys | to_entries[] | select(.value | to_entries[] | select(.key | test("^csrbkp") and .value == $path)) | .key' -- "$DC_DB")
      if [ -n "$index" ]; then
        # Sort csrbkp entries by number and keep only the most recent $keep_backups
        backup_files=$(jq -r --arg idx "$index" '.ssl.keys[$idx] | to_entries[] | select(.key | test("^csrbkp")) | .value' -- "$DC_DB" | sort -V)
        total_backups=$(echo "$backup_files" | wc -l)
        if [ "$total_backups" -gt "$keep_backups" ]; then
          delete_count=$((total_backups - keep_backups))
          echo "$backup_files" | head -n "$delete_count" | while IFS= read -r old_backup; do
            echoi "Backup import_file (index $index): $old_backup"
            if [ "$cleanup_dry_run" != "true" ]; then
              rm -f -- "$old_backup" || {
                echoe "Failed to remove backup import_file: $old_backup"
                continue
              }
              # Remove from index.json
              bkp_key=$(jq -r --arg idx "$index" --arg path "$old_backup" '.ssl.keys[$idx] | to_entries[] | select(.value == $path) | .key' -- "$DC_DB")
              if jq -e "del(.ssl.keys.\"$index\".\"$bkp_key\")" -- "$DC_DB" > "$DC_DB.tmp"; then
                mv -- "$DC_DB.tmp" "$DC_DB" || {
                  echoe
                }
                set_permissions_and_owner "$DC_DB" 600
              else
                echoe "Failed to update index.json for backup import_file: $old_backup"
                continue
              fi
              echos "Removed backup import_file: $old_backup"
            else
                echov "Dry run: Would remove backup import_file: $old_backup"
            fi
          done
        else
            echod "Keeping backup import_file (within limit $keep_backups): $backup_file_path"
        fi
      else
        echoi "Backup import_file (no index): $backup_file_path"
        if [ "$cleanup_dry_run" != "true" ]; then
          rm -f -- "$backup_file_path" || {
              echoe "Failed to remove backup import_file: $backup_file_path"
              continue
          }
          echos "Removed backup import_file: $backup_file_path"
        else
          echov "Dry run: Would remove backup import_file: $backup_file_path"
        fi
      fi
    done
    rm -f -- "$tmpfile_backups" || {
      echoe "Failed rempving"
    }
    if [ "$found_backups" = "false" ]; then
        echoi "No backup files found"
    fi
    echos "Backup import_file cleanup completed"
  fi

  # Clean non-CA keys
  if [ "$cleanup_non_ca_keys" = "true" ]; then
    echoi "Cleaning up non-CA key files..."
    tmpfile_keys=$(mktemp) || { echoe "Failed to create temporary import_file for non-CA keys"; return 1; }
    jq -r '.ssl.keys | to_entries[] | .key + " " + .value.key' -- "$DC_DB" > "$tmpfile_keys"
    found_keys=false
    while IFS= read -r line < "$tmpfile_keys"; do
      found_keys=true
      index=$(echo "$line" | cut -d' ' -f1)
      key_file=$(echo "$line" | cut -d' ' -f2- | sed 's/^"\(.*\)"$/\1/')
      echod "Checking key import_file: $key_file (index $index)"
      # Get CA keys from index.json
      ca_keys=$(jq -r '.ssl.rootCAs // .ssl.intermediateCAs | to_entries[] | .value | to_entries[] | .value | select(.key == "key") | .value' -- "$DC_DB" | sed 's/^"\(.*\)"$/\1/')
      # Skip if key is a CA key
      if echo "$ca_keys" | grep -Fx "$key_file" >/dev/null 2>&1; then
          echod "Key $key_file is a CA key, skipping"
          continue
      fi
      echoi "Non-CA key import_file: $key_file (index $index)"
      if [ "$cleanup_dry_run" != "true" ]; then
          rm -f -- "$key_file" || {
              echoe "Failed to remove non-CA key import_file: $key_file"
              continue
          }
          # Remove the entire index entry
          if jq -e "del(.ssl.keys.\"$index\")" -- "$DC_DB" > "$DC_DB.tmp"; then
              mv -- "$DC_DB.tmp" "$DC_DB" || {
                echoe "Failed moving temporary database $DC_DB"
                return 1
              }
              set_permissions_and_owner "$DC_DB" 600
          else
              echoe "Failed to update index.json for non-CA key: $key_file"
              continue
          fi
          echos "Removed non-CA key import_file: $key_file"
      else
          echov "Dry run: Would remove non-CA key import_file: $key_file"
      fi
    done
    rm -f -- "$tmpfile_keys" >/dev/null
    if [ "$found_keys" = "false" ]; then
        echoi "No non-CA key files found"
    fi
    echos "Non-CA key cleanup completed"
  fi

  # Display cleanup completion message
  if [ "$cleanup_dry_run" = "true" ]; then
      echos "dystopian-crypto cleanup completed successfully (DRY RUN)"
  else
      echos "dystopian-crypto cleanup completed successfully"
  fi
  return 0
}

list_certificate_authorities() {
  ca_list_type="${1:-all}"

  echoi "Certificate Authorities"
  echoi "======================"

  if [ "$ca_list_type" = "all" ] || [ "$ca_list_type" = "root" ]; then
    echoi ""
    echoi "Root CAs:"
    echoi "---------"
    jq -r '.ssl.rootCAs | to_entries[] | .key + " | " + (.value.name // "Unnamed") + " | " + (.value.created // "Unknown date")' -- "$DC_DB" 2>/dev/null | \
    while IFS='|' read -r index name created; do
      printf "  %-12s %-30s %s\n" "$index" "$name" "$created"
      if [ "$VERBOSE" -eq 1 ]; then
        cert_file=$(_get_ca_value "root" "$(echo "$index" | tr -d ' ')" "cert")
        if [ -f "$cert_file" ]; then
          echoi "    Certificate: $cert_file"
          echoi "    Subject: $(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')"
        fi
      fi
    done
  fi

  if [ "$ca_list_type" = "all" ] || [ "$ca_list_type" = "intermediate" ]; then
    echoi ""
    echoi "Intermediate CAs:"
    echoi "-----------------"
    jq -r '.ssl.intermediateCAs | to_entries[] |
           .key + " | " + (.value.name // "Unnamed") + " |
           " + (.value.created // "Unknown date")' -- "$DC_DB" 2>/dev/null | \
    while IFS='|' read -r index name created; do
      printf "  %-12s %-30s %s\n" "$index" "$name" "$created"
      if [ "$VERBOSE" -eq 1 ]; then
        cert_file=$(_get_ca_value "intermediate" "$(echo "$index" | tr -d ' ')" "cert")
        if [ -f "$cert_file" ]; then
          echoi "    Certificate: $cert_file"
          echoi "    Subject: $(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')"
        fi
      fi
    done
  fi
}


key_belongs_to_cert() {
  key_file="$1"
  cert_file="$2"
  keypub=$(openssl ec -in "$key_file" -pubout 2>/dev/null || \
           openssl rsa -in "$key_file" -pubout 2>/dev/null)
  if [ -z "$keypub" ]; then
      echod "Couldn't determine publickey in keyfile: $key_file"
      return 1
  fi
  keypub=$(echo "$keypub" | tail -n +2 | head -n -1)
  certpub=$(openssl x509 -in "$cert_file" -noout -pubkey | tail -n +2 | head -n -1)
  if [ "$keypub" = "$certpub" ]; then
      echod "Publickey of $key_file and $cert_file are identical"
      return 0
  fi
  return 1
}


get_file_type() {
  file="$(realpath "$1")"
  filename="$(basename "$file")"
  ext=${filename##*.}
  type=""

  if [ "$ext" = "conf" ] || [ "$ext" = "cfg" ]; then
    type="cfg"
  elif [ "$ext" = "pem" ] || [ "$ext" = "cert" ] || [ "$ext" = "crt" ] || [ "$ext" = "cer" ]; then
    if grep -qE "PRIVATE KEY" "$file"; then
        type="key"

    elif grep -qE "BEGIN CERTIFICATE" "$file"; then
      if grep -qE "CA:TRUE" "$file" && grep -qE "pathlen:" "$file"; then
          type="intermediate"
      elif grep -qE "CA:TRUE"; then
          type="root"
      else
          type="normal"
      fi
    fi
  fi
  if [ -n "$type" ]; then
      echo "$type"
      return 0
  fi
  return 1
}


check_ssl_database() {
  echoi "Checking database integrity"
  files=$(find "$DC_CA" -type f -maxdepth 1)
  for f in $files; do
    f="$(realpath "$f")"
    ca_name="$(basename "$f" | awk -F. '{print $(NF-1)}')"
    if ! jq -e --arg idx "$ca_name" '.ssl.rootCAs //
                                    .ssl.intermediateCAs | to_entries[] |
                                    select(.key == $idx)' -- "$DC_DB"; then
        echow "File is missing in database: $f"
    fi
  done
}


set_permissions_and_owner() {
  perm="$2"
  if [ "$DYSTOPIAN_USER" = "root" ] && [ "$perm" -eq 440 ]; then
    perm=400
  fi
  if ! chmod -- "$perm" "$1" 2>/dev/null; then
    echoe "Failed to set permissions $perm on $1"
    return 1
  fi
  if ! chown "root:${DYSTOPIAN_USER}" "$1" 2>/dev/null; then
    echoe "Failed to set owner root:${DYSTOPIAN_USER} on $1"
    return 1
  fi
  echod "Successfully set perm ($perm) and owner 'root:$DYSTOPIAN_USER' on $1"
  return 0
}


absolutepath() {
  if which realpath >/dev/null 2>&1; then
    realpath -- "$1"
  else
    dir="$(dirname "$1")"
    basename="${1##*/}"
    echo "$dir/$basename"
  fi
  return 0
}


absolutepathidx() {
  dir="$(dirname "$1")"
  filename="${1##*/}"
  ext="${filename##*.}"
  base="${filename%*".$ext"}"
  case "$OBFUSCATE_FILENAMES" in
    true) idx="$(openssl rand -hex 8)";;
    false) idx="$2";;
  esac
  if [ ! -f "$dir/$base.$idx.$ext" ]; then
      echo "$dir/$base.$idx.$ext"
      return 0
  fi
  c=1
  while [ -f "$dir/$base.$idx.$c.$ext" ]; do
      c=$(("$c" + 1))
  done
  echo "$dir/$base.$idx.$c.$ext"
}


get_index_from_filename() {
  filename="${1##*/}"
  ext="${filename##*.}"
  base="${filename%*".$ext"}"
  if echo "$base" | grep -qE '\.'; then
      echo "$base" | awk -F. '{print $NF}'
      return 0
  fi
  return 1
}


_cleanup() {
  echod "Cleaning up generated files..."
  for file in $DYSTOPIAN_CLEANUP_FILES; do
      rm -rf -- "$file"
  done
  echod "done."
}


set_perms_trap() {
  echod "Setting permissions and ownership..."
  for file in $DYSTOPIAN_PERM_FILES; do
      set_permissions_and_owner "$file" 440
  done
  echod "done."
}


on_exit() {
  set_perms_trap >/dev/null 2>&1
  _cleanup >/dev/null 2>&1
}


get_gh_repo() {
  owner="$1"
  repo="$2"
  curl -s -L \
       -H "Authorization: Bearer $(get_github_token)" \
       -H 'Accept: application/json' \
       "$GH_API_BASE/$owner/$repo" || {
         echoe "Error fetching repo from Github Api"
         return 1
       }
  return 0
}


get_index_from_gpg() {
  if ! gpg --homedir "$DC_GNUPG" --list-keys --keyid-format long "$1" | \
       grep uid | \
       awk -F'[][]' '{print $(NF-0)}' | \
       awk -F' <' '{print $1}' | \
       sed -e 's/\-/\_/g' -e 's/\ /\_/g' | \
       tr "[:upper:]" "[:lower:]"; then
      echoe "Failed getting index from gpg name"
      return 1
  fi
  return 0
}


get_name_from_gpg() {
  if ! gpg --homedir "$DC_GNUPG" --list-keys --keyid-format long "$1" | \
       grep uid | \
       awk -F'[][]' '{print $(NF-0)}' | \
       awk -F' <' '{print $1}'; then
      echoe "Failed getting Name from $1"
      return 1
  fi
  return 0
}


get_email_from_gpg() {
  if ! gpg --homedir "$DC_GNUPG" --list-keys --keyid-format long "$1" | \
       grep uid | \
       awk -F'<' '{print $2}' | \
       awk -F'>' '{print $1}'; then
      echoe "Error getting email address from $1"
      return 1
  fi
  return 0
}


get_fingerprint_from_gpg() {
  if ! gpg --homedir "$DC_GNUPG" --fingerprint --keyid-format long "$1" | \
       grep -i finger | \
       awk -F'= ' '{print $2}'; then
      echoe "Failed getting fingerprint from $1"
      return 1
  fi
  return 0
}


get_subkey_ids_from_gpg() {
  if ! gpg --homedir "$DC_GNUPG" --list-keys --keyid-format long "$1" | \
       grep sub | \
       awk -F'/' '{print $2}' | \
       awk -F' ' '{print $1}'; then
      echoe "Failed getting subkeys from $1"
      return 1
  fi
  return 0
}


create_gpg_filename() {
  index="$1"
  usage="$2"
  armor="${3:-false}"
  typestr="${4:-}"

  if [ "$armor" = "false" ] && { [ "$typestr" = "public" ] || [ "$typestr" = "sub" ]; }; then
      ext="gpg"
  elif [ "$armor" = "false" ] && { [ "$typestr" = "secret" ] || [ "$typestr" = "ssb" ]; }; then
      ext="key"
  elif [ "$armor" = "true" ]; then
      ext="asc"
  fi

  if [ "$usage" = "S" ]; then
      usage="signing"
  elif [ "$usage" = "E" ]; then
      usage="encrypt"
  elif [ "$usage" = "A" ]; then
      usage="auth"
  fi

  echo "$index-$(date "+%Y%m%d_%H%M")-$usage-$typestr.$ext"
}


get_name_real_from_uid() {
  if ! echo "$1" | grep -qE "\(|\)"; then
      echo "$1" | awk -F' <' '{print $1}'
  else
      echo "$1" | awk -F' \\(' '{print $1}'
  fi
}


get_name_email_from_uid() {
  echo "$1" | awk -F' <' '{print $2}' | awk -F'>' '{print $1}'
}


get_name_comment_from_uid() {
  echo "$1" | awk -F' \\(' '{print $2}' | awk -F'\\)' '{print $1}'
}


gpg_build_cmd() {
  [ -n "$1" ] && GPG_CMD="$GPG_CMD --homedir ${1}"
  case "$2" in
    imp)
      GPG_CMD="$GPG_CMD --import";
      [ -z "$5" ] && gpg_cmd="$GPG_CMD --batch";;
    exp) GPG_CMD="$GPG_CMD --export";;
    expsec) GPG_CMD="$GPG_CMD --export-secret-keys";;
    expsecsub) GPG_CMD="$GPG_CMD --export-secret-subkeys";;
    gen) GPG_CMD="$GPG_CMD --quick-gen-key";;
    add) GPG_CMD="$GPG_CMD --quick-add-key";;
    adduid) GPG_CMD="$GPG_CMD --quick-add-uid";;
  esac
  { [ "$2" = "add" ] || [ "$2" = "gen" ] || [ "$2" = "adduid" ]; } && [ -n "$5" ] && GPG_CMD="$GPG_CMD --batch"
  [ "$3" = "true" ] && GPG_CMD="$GPG_CMD -a"
  [ "$4" = "false" ] && GPG_CMD="$GPG_CMD --armor"
  [ -s "$5" ] && GPG_CMD="$GPG_CMD --pinentry-mode loopback --passphrase-file ${5}"
  { { [ -n "$5" ] && [ ! -f "$5" ]; } || [ -z "$5" ]; } && { [ "$2" != "exp" ] && [ "$2" != "imp" ]; } && GPG_CMD="$GPG_CMD --pinentry-mode loopback --passphrase-fd 0"
}


ssl_build_cmd() {
  use="$1"
  in="$2"
  out="$3"
  passphrase="$4"
  no_argon="${5:-false}"
  tpm="${6:-false}"

  SSL_CMD="openssl"
  # Usage scenarios
  [ "$use" = "key" ] && SSL_CMD="$SSL_CMD genpkey"
  [ "$use" = "req" ] && SSL_CMD="$SSL_CMD req"
  [ "$use" = "crt" ] && SSL_CMD="$SSL_CMD x509"
  { [ "$use" = "enc" ] || [ "$use" = "dec" ]; } && SSL_CMD="$SSL_CMD aes-256-cbc"
  [ "$use" = "dec" ] && SSL_CMD="$SSL_CMD -d"
  [ "$use" = "enc" ] && SSL_CMD="$SSL_CMD -e"

  # Check tpm
  { [ "$tpm" = "true" ] && [ "$use" = "crt" ]; } && SSL_CMD="$SSL_CMD -provider tpm2"

  # No argon
  { [ -n "$passphrase" ] && [ "$no_argon" = "true" ]; } && SSL_CMD="$SSL_CMD -pbkdf2"

  # Passphrase
  if [ "$passphrase" != "cli" ] && [ "$passphrase" != "CLI" ]; then
      [ -s "$passphrase" ] && SSL_CMD="$SSL_CMD -pass file:$1"
      { [ -n "$passphrase" ] && [ ! -f "$passphrase" ]; } && SSL_CMD="$SSL_CMD -pass pass:$1"
  fi

  { [ -n "$in" ] && [ "$in" != "stdin" ] && [ "$in" != "-" ]; } && SSL_CMD="$SSL_CMD -in $in"
  { [ -n "$out" ] && [ "$out" != "stdout" ] && [ "$out" != "-" ]; } && SSL_CMD="$SSL_CMD -out $out"

}


check_gpg_key_integrity() {
  tmpdir=$(mktemp -d -- "/tmp/XXXXXXX")
  pubkbx="$tmpdir/pubring.kbx"

  touch -- "$pubkbx" || {
    echoe "Not able to create pubring.kbx for key integrity check."
    return 1
  }

    if grep -qE "BEGIN PGP (PUBLIC|PRIVATE) KEY BLOCK" -- "$1"; then
        gpg --batch --homedir "$tmpdir" --import -- "$1"
    elif file -- "$1" | grep -q "openssl enc"; then
        ssl_build_cmd "$2" "$1"
        $SSL_CMD | gpg --batch --homedir "$tmpdir" --import -- "$1"
    else
        echoe "Key is not a GPG key"
    fi

    if [ "$?" -ne 0 ]; then
        echoe "Key integrity check failed"
        rm -rf -- "$tmpdir"
        return 1
    fi

    rm -rf -- "$tmpdir" || {
      echoe "Failed removing temporary GPG home directory"
      return 1
    }

    return 0
}


install_package() {
    package="$1"

    if [ -f /etc/os-release ]; then
        while read -r line; do
            case "$line" in
                ID=*)
                    distro=$(printf "%s\n" "$line" | sed 's/ID_LIKE=//')
                    if [ -z "$distro" ]; then
                        distro=$(printf "%s\n" "$line" | sed 's/ID=//')
                    fi
                    ;;
            esac
        done < /etc/os-release
    else
        echoe "Cannot detect distribution. /etc/os-release not found."
        return 1
    fi

    case "$distro" in
        ubuntu | debian)
            echov "Detected $distro. Using apt to install $package..."
            # Update package lists
            apt update
            # Install the package
            if apt install -y "$package"; then
                echoi "$package installed successfully"
            else
                echoe "Failed to install $package"
                return 1
            fi
            ;;
        arch)
            echov "Detected Arch Linux. Using pacman to install $package..."
            # Sync and install the package
            if pacman -S --noconfirm "$package"; then
                echoi "$package installed successfully."
            else
                echoe "Failed to install $package"
                return 1
            fi
            ;;
        *)
            echoe "Unsupported distribution: $distro"
            return 1
            ;;
    esac
    return 0
}


trigger_remount_efivars() {
  efiline=$(mount | grep efivars)
  if echo "$efiline" | grep -qE "\(rw"; then
    mount -o ro,remount -- "$EFIVAR_PATH"
  elif echo "$efiline" | grep -qE "\(ro"; then
    mount -o rw,remount -- "$EFIVAR_PATH"
  else
    return 1
  fi
  return 0
}


remount_efivars_rw() {
    echod "Remounting efivars to read/write"
    mount -o rw,remount -- "$EFIVAR_PATH" || {
        echoe "Failed remounting efivars to read/write"
        return 1
    }
    echod "$(mount | grep efivars)"
    return 0
}


remount_efivars_ro() {
    echod "Remounting efivars to read only"
    mount -o ro,remount -- "$EFIVAR_PATH" || {
        echoe "Failed remounting efivars to read only"
        return 1
    }
    echod "$(mount | grep efivars)"
    return 0
}


ssl_convert_der_to_pem() {
    base="${1%.*}"
    echod "Converting DER to PEM:"
    openssl x509 -inform "${1##*.}" -outform pem -in "$1" -out "${1%.*}.pem"
    echod "Converted $1 to ${1%.*}.pem"
}


ssl_convert_pem_to_der() {
    ext="${1##*.}"
    echod "Converting PEM to DER:"
    openssl x509 -inform "${1##*.}" -outform der -in "$1" -out "${1%.*}.der"
    echod "Converted $1 to ${1%.*}.der"
}


download_ms_kek_certs() {
    echoi "Downloading Microsoft Corporation KEK CA 2011 certificate and  Microsoft Corporation KEK 2K CA 2023..."
    pk=$(wget -qO - "")

}


detect_distro() {
    # Detect the distribution
    if [ -f /etc/os-release ]; then
        while read -r line; do
            case "$line" in
                ID=*|ID_LIKE=*)
                    distro=$(printf "%s\n" "$line" | sed 's/ID_LIKE=//')
                    [ -z "$distro" ] && distro=$(printf "%s\n" "$line" | sed 's/ID=//')
                    ;;
            esac
        done < /etc/os-release
    else
        echoe "Cannot detect distribution. /etc/os-release not found."
        return 1
    fi

    echod "Detected distribution: $distro"
}


check_secureboot_status() {
  SECUREBOOT_ENABLED=$(
    od --address-radix=n \
       --format=u1 "$EFIVAR_PATH/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c" | \
    awk -F' ' '{print $NF}'
  )
  if [ "$?" -ne 0 ]; then
    echoe "Failed checking secureboot status"
    return 1
  fi
  return 0
}


get_gh_repo_release() {
  owner="$1"
  repo="$2"
  curl -s -L \
       -H "Authorization: Bearer $(get_github_token)" \
       -H "Accept: application/json" \
       "$GH_API_BASE/$owner/$repo/releases" || {
         echoe "Error fetching release from Github Api"
         return 1
       }
  return 0
}


backup_targz() {
  path="${1:+$(absolutepath "$1")}"
  [ -d "$path" ] || return 0
  dirname="$(echo "$path" | awk -F'/' '{print $NF}')"
  parent="${path%"$dirname"}"
  [ -d "$parent" ] || return 0
  # choose a timestamped name (YYYYmmdd_HHMMSS) and avoid collisions by adding a counter
  ts="$(date +%Y%m%d_%H%M%S)"
  outfile="${dirname}.bkp.${ts}.tar.gz"
  cnt=0
  while [ -e "$outfile" ]; do
    cnt=$((cnt + 1))
    outfile="${dirname}.bkp.${ts}.${cnt}.tar.gz"
  done
  # create tarball from parent so archive contains base/...
  if tar -C "$parent" -czf "$outfile" -- "$dirname" 2>/dev/null; then
    printf 'Created backup: %s\n' "$outfile"
  else
    printf 'Failed to create backup: %s\n' "$outfile" >&2
    rm -f -- "$outfile" || true
    return 1
  fi
  return 0
}


preparse() {
    DC_POS_ARGS=""
    mcmd="$1"
    shift
    while [ $# -gt 0 ]; do
        if [ "$1" = "--user" ] && echo "$mcmd" | grep -qE "hosts$|aurtool$"; then
            if [ $# -gt 1 ]; then
                DYSTOPIAN_USER="$2"; shift 2
            else
                echoe "--user requires an argument"; exit 1
            fi
        fi
        case "$1" in
            --verbose|-v) VERBOSE=1; shift;;
            --quiet|-q) DEBUG=0; VERBOSE=0; QUIET=1; shift;;
            --debug) DEBUG=1; VERBOSE=1; shift;;
            --external|--ext|--usb|--external=*|--ext=*|--usb=*)
              USB_STORAGE=
              shift
              ;;
            *)
                if [ -z "$DC_POS_ARGS" ]; then
                    DC_POS_ARGS=$1
                else
                    DC_POS_ARGS=$DC_POS_ARGS"||$1"
                fi
                [ "$#" -gt 0 ] && shift
                ;;
        esac
    done
}


download_and_install_latest_releases() {
  cwd="$1"
  tmpdir=$(mktemp -d ./XXXXXX)
  cd -- "$tmpdir" || {
    echoe "Failed changing directory: $tmpdir"
    return 1
  }
  for pkg in "${DYSTOPIAN_PACKAGES[@]}"; do
    url=$(curl -s "https://api.github.com/repos/dcx7c5/$pkg/releases" | jq -r '.[0].assets[0].browser_download_url') && \
    wget -qO- "$url" | tar -xvzf - && \
    sudo make -C "$pkg" install
  done
  cd -- "$cwd" || {
    echoe "Failed changing directory: $tmpdir"
    return 1
  }
  if ! rm -rf "$tmpdir"; then
    echo "Error removing $tmpdir"
    return 1
  fi
}


cleanup_stack_gpghome() {
  rm -rf -- "$PROJECT_DIR/.certs/.gnupg" || {
    echoe "Failed removing"
    return 1
  }
  export GNUPGHOME=$OLDGNUPGHOME
}


format_storage() {
  stor_path="$1"
  max_storage="${2:-2G}"
  size_fat32="${3:-129MiB}"

  if ! askyesno "Do you really want to format the storage device?" "n"; then
    echoi "Aborted formating storage device $stor_path"
    exit 0
  fi
  umount "${stor_path}*" 2>/dev/null || true

  if ! askyesno "Are you sure you want to wipe the storage device??" "n"; then
    echoi "Aborted."
    exit 0
  fi

  wipefs -a "$stor_path"
  parted -s "$stor_path" mklabel gpt
  parted -s "${stor_path}" mkpart primary fat32 1MiB "$size_fat32"
  parted -s "${stor_path}" mkpart primary "$size_fat32" "$max_storage"
  mkfs.vfat -F 32 -n "UEFI_Update" "${stor_path}1"

  cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    --pbkdf argon2id \
    --sector-size 4096 \
    "${stor_path}2"

  USB_SERIAL=$(
    lsblk -o NAME,SIZE,MODEL,SERIAL,LABEL,MOUNTPOINT,FSTYPE \
      | grep -E "$stor_path" \
      | head -1 \
      | awk -F' ' '{print $NF-1}'
    )

  cryptsetup luksOpen "${stor_path}2" usb_crypt
  mkfs.ext4 -L "${USB_LABEL:-DYSTO_CERTS}" /dev/mapper/usb_crypt
  cryptsetup close usb_crypt


  sed -i "s/# USB_SERIAL*|USB_SERIAL*/USB_SERIAL=$(id -u).$USB_SERIAL/" -- "$DC_CFG"
  set_permissions_and_owner "$DC_CFG" 600
  echos "Successfully formated USB storage devices ${stor_path} - ${USB_LABEL}"
}


usb_storage_missing() {
  counter=0
  counter_max="${COUNTER_MAX:-5}"
  device_id="${1:-$USB_DEVICE_ID}"
  device_path="sd$(lsblk -o NAME,SIZE,MODEL,SERIAL,LABEL,MOUNTPOINT,FSTYPE \
    | grep -E "$device_id" -A3 \
    | grep -E "crypto_LUKS" \
    | awk -F'sd' '{print $2}' \
    | awk -F' ' '{print $1}')"
  echow "USB Storage Device not found or plugged in!"

  while [ $counter -le "$counter_max" ]; do
    if askyesno "Insert Storage Device ${device_path} and press Enter:" "y"; then
      if [ ! -f "$device_path" ]; then
        echosv "USB storage device "
      fi
    else
      :
    fi
    counter=$(("$counter" + 1))
  done
}

_manage_system_truststore() {
  index="$1"
  type="$2"
  ck_path="$3"
  process="$4"
  ca_name="$5"
  perms="444"

  if [ "$type" != "cert" ]; then
      echoe "Only cert type supported"
      return 1
  fi

  # Consistent filename: index.crt
  slug="$index.crt"
  ts_anchors="/etc/ca-certificates/trust-source/anchors"
  ts_path="$ts_anchors/$slug"

  if [ "$process" = "install" ]; then
    echoi "Installing certificate into system trust store..."

    # Manual fallback for p11-kit systems (Arch, etc.)
    if [ -d "$ts_anchors" ]; then
      echov "Detected p11-kit anchors directory (e.g. Arch Linux)."
      # Preferred modern way: trust anchor --store (works on Arch, Fedora, etc.)
      if command -v trust >/dev/null 2>&1; then

        if trust anchor "$ck_path" >/dev/null 2>&1; then
          echod "Certificate installed from system trust database via 'trust anchor' (p11-kit)."
          return 0
        else
          echow "'trust anchor --store' failed, falling back to manual placement."
        fi
      else
        cp "$ck_path" "$ts_path" || {
          echoe "Failed to copy certificate"
          return 1
        }
        set_permissions_and_owner "$ts_path" "$perms"
      fi

      if update-ca-trust >/dev/null 2>&1; then
          echosv "Certificate installed in system trust database (manual p11-kit)."
          return 0
      else
          echoe "Failed to run 'trust update-ca-trust'"
          return 1
      fi

    # Debian/Ubuntu fallback
    elif [ -d /usr/local/share/ca-certificates ]; then
      echov "Detected Debian/Ubuntu style trust store."
      ts_path="/usr/local/share/ca-certificates/$index/$slug"
      cp "$ck_path" "$ts_path" || { echoe "Failed to copy certificate"; return 1; }
      set_permissions_and_owner "$ts_path" "$perms"
      if update-ca-certificates; then
          echosv "Certificate installed in system trust database (Debian/Ubuntu)."
          return 0
      else
          echoe "Failed to run 'update-ca-certificates'"
          return 1
      fi

    else
      echow "No recognized system trust store found. Skipping system-wide install."
      echow "Applications may still trust via NSS or p11-kit."
      return 1
    fi

  elif [ "$process" = "uninstall" ]; then
    echoi "Uninstalling certificate from system trust store..."
    removed=0

    # Preferred: trust anchor --remove
    if command -v trust >/dev/null 2>&1; then
      if trust anchor --remove "$(trust list | grep -B3 "$ca_name" | head -1)" >/dev/null 2>&1; then
          echosv "Certificate uninstalled from system trust store via 'trust anchor --remove'."
          return 0
      fi
    fi

    # Manual removal
    if [ -d "$ts_anchors" ]; then
      echov "Detected p11-kit anchors directory."
      ts_path="$ts_anchors/$slug"
      if [ -f "$ts_path" ]; then
          rm -f "$ts_path"
          echov "Removed $ts_path"
          removed=1
      fi
      if trust extract-compat; then
          if [ "$removed" = 1 ]; then
              echosv "Certificate uninstalled from system trust store (manual p11-kit)."
          fi
      else
          echoe "Failed to run 'trust extract-compat'"
          return 1
      fi

    elif [ -d /usr/local/share/ca-certificates ]; then
      echov "Detected Debian/Ubuntu style."
      ts_path="/usr/local/share/ca-certificates/$slug"
      if [ -f "$ts_path" ]; then
          rm -f "$ts_path"
          echov "Removed $ts_path"
          removed=1
      fi
      if update-ca-certificates --fresh; then
          if [ "$removed" = 1 ]; then
              echosv "Certificate uninstalled from system trust store (Debian/Ubuntu)."
          fi
      else
          echoe "Failed to run 'update-ca-certificates'"
          return 1
      fi

    else
        echow "No recognized system trust store found. Assuming already uninstalled."
        return 1
    fi

    if [ "$removed" = 0 ]; then
        echow "Certificate not found in system trust store – assuming already uninstalled."
    fi
    echosv "Uninstallation from system trust store completed"

  else
      echoe "Invalid process: $process"
      return 1
  fi

  echosv "Truststore operation successful"
  return 0
}


_manage_browser_truststore() {
    name="$1"
    index="$2"
    trust_type="$3"
    ck_path="$4"
    process="$5"
    processed=0

    if [ "$process" = "install" ]; then

        if [ "$trust_type" = "firefox" ] && [ -d "/home/${DYSTOPIAN_USER}/.mozilla/firefox" ]; then
            for profile_dir in "/home/${DYSTOPIAN_USER}/.mozilla/firefox"/*/; do
                # Check if directory exists and has a cert db
                if [ -f "${profile_dir}cert9.db" ] || [ -f "${profile_dir}cert8.db" ]; then
                    if certutil -d sql:"$profile_dir" -A -t "C,," -n "$name" -i "$ck_path" >/dev/null 2>&1; then
                        echosv "Updated Firefox profile: $(basename "$profile_dir")"
                        processed=$((processed + 1))
                    fi
                fi
            done
        fi

        if [ "$trust_type" = "chrome" ] && [ -d "/home/${DYSTOPIAN_USER}/.pki/nssdb" ]; then
            if certutil -d sql:"/home/${DYSTOPIAN_USER}/.pki/nssdb" -A -t "C,," -n "$name" -i "$ck_path" >/dev/null 2>&1; then
                echosv "Updated Chrome/Chromium/Edge/Brave NSS database."
                processed=$((processed + 1))
            fi
        fi

        if [ "$processed" -gt 0 ]; then
            echov "Please fully restart all browsers for changes to take effect."
            echosv "Certificate installation to browser trust stores successful ($processed location(s))."
            return 0
        else
            echow "No compatible NSS databases found for installation."
            return 1
        fi

    elif [ "$process" = "uninstall" ]; then

        if [ "$trust_type" = "firefox" ] && [ -d "/home/${DYSTOPIAN_USER}/.mozilla/firefox" ]; then
            for profile_dir in "/home/${DYSTOPIAN_USER}/.mozilla/firefox"/*/; do
                if [ -f "${profile_dir}cert9.db" ] || [ -f "${profile_dir}cert8.db" ]; then
                    if certutil -d sql:"$profile_dir" -D -n "$name" >/dev/null 2>&1; then
                        echosv "Removed from Firefox profile: $(basename "$profile_dir")"
                        processed=$((processed + 1))
                    fi
                fi
            done
        fi

        if [ "$trust_type" = "chrome" ] && [ -d "/home/${DYSTOPIAN_USER}/.pki/nssdb" ]; then
            if certutil -d sql:"/home/${DYSTOPIAN_USER}/.pki/nssdb" -D -n "$name" >/dev/null 2>&1; then
                echosv "Removed from Chrome/Chromium/Edge/Brave NSS database."
                processed=$((processed + 1))
            fi
        fi

        if [ "$processed" -gt 0 ]; then
            return 0
        else
            echow "Certificate '$name' not found in any targeted browser trust stores."
            return 1
        fi

    else
        echoe "Invalid process: $process"
        return 2
    fi
}


manage_truststore() {
  ca_name="$1"
  index=$(echo "$ca_name" | sed -e 's/[- ]/_/g' | tr '[:upper:]' '[:lower:]')
  process="$2"
  stores="${3:-}"
  cmd="${4:-false}"

  if [ -z "$ca_name" ]; then
    echoe "Certificate name is required"
    return 1
  elif [ -z "$process" ]; then
    echoe "Management type has to be set (install/uninstall)"
    return 1
  fi

  ca_cert_path=$(get_value_from_index "$index" "cert")
  if [ -z "$ca_cert_path" ]; then
    echow "Certificate path not found for index $index"
    return 1
  fi

  ca_stor_type=$(get_value_from_index "$index" "type")
  case "$index" in
    "$ca_name") ca_name=$(get_value_from_index "$index" "name") ;;
  esac

  echod "Starting manage_truststore with parameters:"
  echod "            index: $index"
  echod "          ca_name: $ca_name"
  echod "          process: $process"
  echod "           stores: $stores"
  echod "     ca_cert_path: $ca_cert_path"
  echod "     ca_stor_type: $ca_stor_type"

  if [ "$process" = "uninstall" ] && [ -z "$stores" ]; then
    stores=$(get_value_from_index "$index" "truststores")
    if [ -z "$stores" ]; then
      echod "Certificate with index: $index not found in any truststores"
      return 0
    fi
  elif [ "$process" = "install" ] && [ -z "$stores" ]; then
    stores="system,chrome,firefox"
  fi

  case "$stores" in
    *[Ff][Ii][Rr][Ee]*|*[Ff][Oo][Xx]*|*[Cc][Hh][Rr][Oo][Mm][Ee]*)
      [ "$DYSTOPIAN_USER" = "root" ] && \
        echoe "Browser trust requires non-root user (use --user when logged in as root, or use sudo)" && \
        return 1
        ;;
  esac

  if ! command -v certutil >/dev/null 2>&1; then
    echoe "certutil not found (nss-tools required)"
    return 1
  fi

  if [ "$process" = "install" ] || [ "$process" = "uninstall" ]; then
    oldIFS=$IFS status=0 IFS=,
    for i in $stores; do
      case "$i" in
        *[Ss][Yy][Ss]*)
          echod "Calling _manage_system_truststore \"$index\" \"cert\" \"$ca_cert_path\" \"$process\" \"$ca_name\""
          _manage_system_truststore "$index" "cert" "$ca_cert_path" "$process" "$ca_name"
          case $? in 0) : ;; *) status=1;; esac
          ;;
        *[Cc][Hh][Rr][Oo][Mm][Ee]*)
          echod "Calling _manage_browser_truststore \"$ca_name\" \"$index\" \"chrome\" \"$ca_cert_path\" \"$process\""
          _manage_browser_truststore "$ca_name" "$index" "chrome" "$ca_cert_path" "$process"
          case $? in 0) : ;; *) status=1 ;; esac
          ;;
        *[Ff][Ii][Rr][Ee]*|*[Ff][Oo][Xx]*)
          echod "Calling _manage_browser_truststore \"$ca_name\" \"$index\" \"firefox\" \"$ca_cert_path\" \"$process\""
          _manage_browser_truststore "$ca_name" "$index" "firefox" "$ca_cert_path" "$process"
          case $? in 0) : ;; *) status=1 ;; esac
          ;;
      esac
    done
    IFS=$oldIFS

    # Update data.json if called as command (original logic)
    if [ "$cmd" = true ]; then
      [ "$process" = "install" ] && value="$stores" || value=""
      case "$ca_stor_type" in
        server|client) add_to_ssl_certs "$index" "truststores" "$value";;
        root) add_to_ca_database "root" "$index" "truststores" "$value";;
        intermediate) add_to_ca_database "$ca_stor_type" "$index" "truststores" "$value";;
      esac
    fi
    if [ "$status" -eq 0 ]; then
      echosv "Successfully processed $index: cert for $stores trust databases."
      return 0
    else
      echow "One or more trust operations failed."
      return 1
    fi

  elif [ "$process" = "cleanup" ]; then
    indices=$(get_all_indices)
    while read -r idx; do
      datastores=$(get_value_from_index "$idx" "truststores")
      { [ -z "$datastores" ] || [ "$datastores" = '' ] || [ "$datastores" = null ]; } && continue
      # TODO: Implement cleanup for orphaned NSS database entries (idx in data.json, mhhhh)
    done < "$indices"
  fi
}


prompt_passphrase() {
  oldtty=$(stty -F /dev/tty -g 2>/dev/null || echo '')
  trap 'stty -F /dev/tty "$oldtty" 2>/dev/null || stty -F /dev/tty sane 2>/dev/null' INT TERM HUP
  stty -F /dev/tty -echo 2>/dev/null
  secret=1 secret2=2
  if [ "$1" = true ]; then
    while [ "$secret" != "$secret2" ]; do
      echow "Enter pass phrase for $2: " "tty"
      IFS= read -r secret </dev/tty
      printf '\n' >/dev/tty
      echow "Verifying - Enter pass phrase for $2: " "tty"
      IFS= read -r secret2 </dev/tty
    done
  else
    echow "Enter pass phrase: " "tty"
    IFS= read -r secret </dev/tty
  fi

  printf '%s' "$secret"
  stty -F /dev/tty "$oldtty" 2>/dev/null || stty -F /dev/tty sane 2>/dev/null
  printf '\n' >/dev/tty
  unset secret secret2
}


init_gpg_env() {
  export GNUPGHOME="${1:-$DC_GNUPG}"
  if [ ! -d "$GNUPGHOME" ]; then
    mkdir -p -- "$GNUPGHOME/gpg.conf.d" || {
      echoe "Failed creating gnupg home directory"
      return 1
    }

  fi
  if [ ! -f "$GNUPGHOME/gpg.conf.d/trust.conf" ]; then
    touch "$GNUPGHOME/gpg.conf.d/trust.conf"
    echo "trust-model always" | tee "$GNUPGHOME/gpg.conf.d/trust.conf"
  fi
  if [ ! -f "$GNUPGHOME/pubring.kbx" ]; then
    gpg --list-secret-keys >/dev/null 2>&1 || true
  fi
  [ -n "$GNUPGHOME" ] && echosv "Successfully setup GNUPGHOME"
}


create_tmp_gpg_home() {
  tmpdir="$(mktemp -d -- /tmp/XXXXXXXXX)"
  init_gpg_env "$tmpdir" || return 1
  echo "$tmpdir"
  return 0
}


create_gpg_home() {
  init_gpg_env || return 1
  echo "$GNUPGHOME"
  return 0
}


exec_as_user() {
  su - "$DYSTOPIAN_USER" -c "$@"
}


install_to_fritzbox() {
  host="${1:-"https://192.168.178.1"}"
  host="${host%/}"
  pass="${2:+$([ -s "$2" ] && absolutepath "$2" || echo "$pass")}"
  passdbg=$({ [ -n "${2}" ]  && [ ! -f "${2}" ]; } && echo "[SET]" || echo "${2}")
  username="$3"
  certpass="$4"
  certpassdbg=$({ [ -n "${4}" ]  && [ ! -f "${4}" ]; } && echo "[SET]" || echo "${4}")
  name="$5"

  debugv="$([ "$DEBUG" -eq 1 ] && echo "-v " || echo "")"
  index=$(echo "$name" | sed -e 's/[- ]/_/g' | tr '[:upper:]' '[:lower:]')
  [ "$index" = "$name" ] && name="$(get_value_from_index "$index" "name")"
  tmpfile="$(mktemp -t XXXXXX)"
  tmpcert="$(mktemp -t XXXXXX.pem)"

  echoi "Installing certificate: $name on $host"

  echod "Starting install_to_fritzbox with:"
  echod "       host: $host"
  echod "       pass: $passdbg"
  echod "   username: $username"
  echod "   certpass: $certpassdbg"
  echod "       name: $name"

  echov "Initiating challenge..."

  echod "Calling curl -sS \"$host/login_sid.lua\" | cat | sed -ne 's/^.*<Challenge>\([0-9a-f][0-9a-f]*\)<\/Challenge>.*$/\1/p'"
  challenge="$({ curl -sS "$host/login_sid.lua" | cat | sed -ne 's/^.*<Challenge>\([0-9a-f][0-9a-f]*\)<\/Challenge>.*$/\1/p'; } 2>/dev/null)"
  if [ -z "${challenge}" ]; then
    echoe "Invalid challenge received."
    return 1
  else
    echod "Challenge received: $challenge"
  fi

  echov "Creating md5sum..."
  if [ -s "$pass" ]; then
    md5hash="$(printf "%s" "$challenge-$(tr -d '\n' <"$pass")" | iconv -f ASCII -t UTF-16LE | md5sum | tr -d '\n\- ')"
  else
    md5hash="$(printf "%s" "$challenge-$pass" | iconv -f ASCII -t UTF-16LE | md5sum | tr -d '\n\- ')"
  fi
  if [ -z "${md5hash}" ]; then
    echoe "Failed creating md5hash."
    return 1
  else
    echod "md5 created: $md5hash"
  fi

  echov "Submitting challenge and log in..."
  echod "Calling curl -sS \"$host/login_sid.lua?username=$username&response=$challenge-$md5hash\" | cat | sed -ne 's/^.*<SID>\([0-9a-f][0-9a-f]*\)<\/SID>.*$/\1/p'"
  sid="$({ curl -sS "$host/login_sid.lua?username=$username&response=$challenge-$md5hash" | cat | sed -ne 's/^.*<SID>\([0-9a-f][0-9a-f]*\)<\/SID>.*$/\1/p'; } 2>/dev/null)"
  if [ -z "${sid}" ] || [ "${sid}" = "0000000000000000" ]; then
    echoe "Login failed."
    return 1
  else
    echosv "Login successful."
    echod "Received SID: $sid."
  fi

  # generate our upload request
  certbundle=$(cat "$(get_value_from_index "$index" "key")" "$(get_value_from_index "$index" "fullchain")"  | grep -v '^$')
  boundary="---------------------------$(date +%Y%m%d%H%M%S)"

cat <<EOD >>"${tmpfile}"
--${boundary}
Content-Disposition: form-data; name="sid"

${sid}
--${boundary}
Content-Disposition: form-data; name="BoxCertImportFile"; filename="BoxCert.pem"
Content-Type: application/octet-stream

${certbundle}
--${boundary}--
EOD

  echov "Uploading certificate..."
  success_msgs="^ *(Das SSL-Zertifikat wurde erfolgreich importiert|Import of the SSL certificate was successful|El certificado SSL se ha importado correctamente|Le certificat SSL a été importé|Il certificato SSL è stato importato( correttamente)?|Import certyfikatu SSL został pomyślnie zakończony)\.$"
  echod "Calling curl -sS -X POST \"${host}/cgi-bin/firmwarecfg\" -H \"Content-type: multipart/form-data boundary=${boundary}\" --data-binary \"@${tmpfile}\" | cat ..."
  { curl -sS -X POST "${host}/cgi-bin/firmwarecfg" -H "Content-type: multipart/form-data boundary=${boundary}" --data-binary "@${tmpfile}" | cat | grep -qE "${success_msgs}"; } 2>/dev/null
  if [ $? -ne 0 ]; then
    echoe "Could not import certificate to $name."
    return 1
  else
    echos "Successfully uploaded & installed certificate: $name on $host."
    return 0
  fi
}

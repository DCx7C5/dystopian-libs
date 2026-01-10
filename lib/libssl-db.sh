# shellcheck shell=sh
# shellcheck disable=SC2001

# Set secure umask for all temporary file operations in this library
umask 077


get_value_from_index() {
  if [ $# -eq 2 ]; then
    jq -r --arg idx "$1" \
          --arg value "$2" \
          '.ssl.rootCAs[$idx][$value] //
           .ssl.intermediateCAs[$idx][$value] //
           .ssl.certs[$idx][$value] //
           empty' -- "$DC_DB" || return 1

  elif [ $# -eq 1 ]; then
    jq -r --arg idx "$1" \
          '.ssl.rootCAs[$idx] //
           .ssl.intermediateCAs[$idx] //
           .ssl.certs[$idx] //
           empty' -- "$DC_DB" || return 1
  fi
  return 0
}


get_value_from_ca_index() {
  if [ $# -eq 2 ]; then
    jq -r --arg idx "$1" \
          --arg value "$2" \
          '.ssl.rootCAs[$idx][$value] // .ssl.intermediateCAs[$idx][$value] // empty' -- "$DC_DB" || {
            echoe "Failed getting value from db file"
            return 1
        }
  elif [ $# -eq 1 ]; then
    jq -r --arg idx "$1" \
          '.ssl.rootCAs[$idx] // .ssl.intermediateCAs[$idx] // empty' -- "$DC_DB" || {
            echoe "Failed getting value from db file"
            return 1
          }
  fi
  return 0
}


get_value_from_certs_index() {
  if [ $# -eq 2 ]; then
    jq -r --arg idx "$1" \
          --arg value "$2" \
          '.ssl.certs[$idx][$value] // empty' -- "$DC_DB" || {
      echoe "Failed getting value from db file"
      return 1
    }
  elif [ $# -eq 1 ]; then
    jq -r --arg idx "$1" \
          '.ssl.certs[$idx] // empty' -- "$DC_DB" || {
      echoe "Failed getting value from db file"
      return 1
    }
  fi
  return 0
}


get_value_from_caroot() {
  if [ $# -eq 2 ]; then
    jq -r --arg idx "$1" \
          --arg value "$2" \
          '.ssl.rootCAs[$idx][$value] // empty' -- "$DC_DB" || {
            echoe "Failed getting value from db file"
            return 1
        }
  elif [ $# -eq 1 ]; then
    jq -r \
       --arg idx "$1" \
       '.ssl.rootCAs[$idx] // empty' -- "$DC_DB" || {
      echoe "Failed getting value from db file"
      return 1
    }
  fi
  return 0
}


get_value_from_caint() {
  if [ $# -eq 2 ]; then
    jq -r --arg idx "$1" \
          --arg value "$2" \
          '.ssl.intermediateCAs[$idx][$value] // empty' -- "$DC_DB" || {
      echoe "Failed getting value from db file"
      return 1
    }
  elif [ $# -eq 1 ]; then
    jq -r --arg idx "$1" \
          '.ssl.intermediateCAs[$idx] // empty' -- "$DC_DB" || {
      echoe "Failed getting value from db file"
      return 1
    }
  fi
  return 0
}


has_defaultRootCA() {
  jq -e '.defaultRootCA? // "" | (type == "string") and (length > 0)' -- "$DC_DB" >/dev/null 2>&1
}


has_defaultCA() {
  jq -e '.defaultCA? // "" | (type == "string") and (length > 0)' -- "$DC_DB" >/dev/null 2>&1
}


find_defaultCA() {
  if has_defaultCA; then
    jq -r '.defaultCA // empty' -- "$DC_DB" || {
      echoe "Not able to get defaultCA entry"
      return 1
    }
  elif has_defaultRootCA; then
    jq -r '.defaultRootCA // empty' -- "$DC_DB" || {
      echoe "Not able to get defaultCA entry"
      return 1
    }
  else
    echoe "No defaultCA values found"
    return 1
  fi
  return 0
}


get_defaultCA() {
  jq -r '.defaultCA // empty' -- "$DC_DB" || {
    echoe "Failed getting defaultCA"
    return 1
  }
}


get_defaultRootCA() {
  jq -r '.defaultRootCA // empty' -- "$DC_DB" || {
    echoe "Failed getting defaultRootCA"
    return 1
  }
  return 0
}


get_defaultCA_key() {
  index=$(jq -r '.defaultCA // empty' -- "$DC_DB")
  if [ -z "$index" ]; then
    echoe "Couldn't load defaultCA index name from database"
    return 1
  fi
  get_value_from_ca_index "$index" "key"
}


get_defaultCA_cert() {
  index=$(jq -r '.defaultCA // empty' -- "$DC_DB")
  if [ -z "$index" ]; then
    echoe "Couldn't load defaultCA index name from database"
    return 1
  fi
  get_value_from_ca_index "$index" "cert"
}


reset_ssl_index() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  # Reset SSL section to default state
  if jq '.defaultRootCA = "" |
         .defaultCA = "" |
         .ssl = {
            encrypted: {},
            certs: {},
            rootCAs: {},
            intermediateCAs: {}
    }' -- "$DC_DB" > "$temp_file"; then
    mv -- "$temp_file" "$DC_DB" || {
      echoe "Failed to reset SSL index"
      rm -f -- "$temp_file" || true
      return 1
    }
  fi
  echosv "SSL index reset to default state"
}



set_defaultCA() {
  index="$1"

  # Check index exists in database
  if ! has_index "$index"; then
    echoe "Index: $index not found in database."
    return 1
  fi

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX")
  jq -e --arg idx "$index" '.defaultCA = $idx' -- "$DC_DB" > "$temp_file" || {
    echoe "Setting $index as defaultCA failed"
    rm -f -- "$temp_file"
    return 1
  }

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Overwriting database with temporary db failed"
    rm -f -- "$temp_file"
    return 1
  }

  echod "Updating defaultCA successful: $1"
  return 0
}

set_defaultRootCA() {
  index="$1"

  # Check index exists in database
  if ! has_index "$index"; then
    echoe "Index: $index not found in database."
    return 1
  fi

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX")
  jq -e --arg idx "$index" '.defaultRootCA = $idx' -- "$DC_DB" > "$temp_file" || {
    echoe "Setting $index as defaultRootCA failed"
    rm -f -- "$temp_file"
    return 1
  }

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Overwriting database with temporary db failed"
    rm -f -- "$temp_file"
    return 1
  }
  echod "Updating defaultRootCA successful: $1"
  return 0
}


delete_key_from_index() {
  index="$1"
  key="$2"

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  file=$(jq -r \
            --arg idx "$index" \
            --arg key "$key" \
            '.ssl.certs[$idx][$key] // empty' -- "$DC_DB")

  jq -r --arg idx "$index" --arg key "$key" 'del(.ssl.certs[$idx][$key])' -- "$DC_DB" > "$temp_file" || {
    echoe "Failed deleting key: $key from ssl: $index"
    rm -f -- "$temp_file" || {
      echoe "Failed removing file: $file"
    }
    return 1
  }

  if [ -s "$file" ]; then
    rm -f -- "$file" || {
      echoe "Failed removing file: $file"
      return 1
    }
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed moving $DC_DB"
    rm -f -- "$temp_file" || true
    return 1
  }

  return 0
}


delete_key_from_ca_index() {
  index="$1"
  key="$2"
  file_delete="${3:-true}"

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if [ "$file_delete" = "true" ]; then
    file="$(jq -r --arg idx "$index" --arg key "$key" '.ssl.intermediateCAs[$idx][$key] // .ssl.rootCAs[$idx][$key] // empty' -- "$DC_DB")"
    rm -f -- "$file"
  fi

  jq -r --arg idx "$index" --arg key "$key" 'del(.ssl.rootCAs[$idx][$key]) // del(.ssl.intermediateCAs[$idx][$key])' -- "$DC_DB" > "$temp_file" || {
    echoe "Failed deleting "
    rm -f -- "$temp_file"
    return 1
  }

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed moving $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }

  return 0
}


default_ca_exists() {
    if jq -e '.defaultCA // empty' -- "$DC_DB" >/dev/null; then
        return 0
    fi
    return 1
}


root_ca_index_exists() {
  if jq -e \
        --arg idx "$1" \
        '.ssl.rootCAs[$idx]
        // empty' -- "$DC_DB" >/dev/null 2>&1; then
        return 0
  fi
  return 1
}


int_ca_index_exists() {
  if jq -e \
      --arg idx "$1" \
      '.ssl.intermediateCAs[$idx]
      // empty' -- "$DC_DB" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}


cert_index_exists() {
  if jq -e \
      --arg idx "$1" \
      '.ssl.certs[$idx]? // "empty" | (type == "string") and (length > 0)' -- "$DC_DB" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}


add_to_ssl_certs() {
  index="$1"
  key="$2"
  value="$3"

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq --arg idx "$1" \
          --arg key "$2" \
          --arg value "$3" \
          '.ssl.certs[$idx][$key] = $value' -- "$DC_DB" > "$temp_file"; then
    echoe "Failed to add $2 to index"
    rm -f -- "$temp_file" || {
      echoe "Faile removing temporary file: $temp_file"
    }
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
      echoe "Failed to move temporary database file to $DC_DB"
      rm -f -- "$temp_file"
      return 1
  }
  echod "Updating ssl keys database successful for ssl: certs: $1: $2 = $3"
  return 0
}


add_to_ca_database() {
  index="$2"
  key="$3"
  value="$4"

  case "$1" in
    root|rootCAs) storage_type="rootCAs";;
    intermediate|intermediateCAs) storage_type="intermediateCAs";;
  esac

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq --arg typ "$storage_type" \
        --arg idx "$index" \
        --arg key "$key" \
        --arg val "$value" \
        '.ssl[$typ][$idx][$key] = $val' -- "$DC_DB" > "$temp_file"; then
    echoe "Failed to update CA database for ssl: $storage_type: $index: $key"
    rm -f -- "$temp_file"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }
  echod "Updating ssl CA database successful for ssl: $storage_type: $index: $key = $value"
  return 0
}


has_index() {
  if [ $# -eq 2 ]; then
    if jq -e \
       --arg idx "$1" \
       --arg typ "$2" \
       '.ssl.certs[$idx]? // empty | (type == "object")' -- "$DC_DB" >/dev/null 2>&1; then
      return 0
    fi
  elif [ $# -eq 1 ]; then
    if jq -e \
       --arg idx "$1" \
       '.ssl.certs[$idx]? //
        .ssl.rootCAs[$idx]? //
        .ssl.intermediateCAs[$idx]? //
        empty | (type == "object")' -- "$DC_DB" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}


find_index_by_key_value() {
    if ! jq -r \
            --arg key "$1" \
            --arg value "$2" \
            '.ssl.certs + .ssl.rootCAs + .ssl.intermediateCAs | to_entries[] | select(.value[$key] == $value) | .key //
             empty' -- "$DC_DB"; then
        return 1
    fi
    return 0
}


find_certs_index_by_key_value() {
  if ! jq -r \
          --arg key "$1" \
          --arg val "$2" \
          '.ssl.certs | to_entries[] | select(.value[$key] == $val) | .key //
           empty' -- "$DC_DB"; then
      return 1
  fi
  return 0
}


find_ca_index_by_key_value() {
  if ! jq -r \
        --arg key "$1" \
        --arg val "$2" \
        '.ssl.rootCAs + .ssl.intermediateCAs | to_entries[] | select(.value[$key] == $val) | .key //
         empty' -- "$DC_DB"; then
    return 1
  fi
  return 0
}


cleanup_ca_index() {
  ca_type="$1"
  ca_index="$2"

  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq -e --arg type "$ca_type" \
        --arg idx "$ca_index" \
        'del(.ssl[$type][$idx])' -- "$DC_DB" > "$temp_file"; then
    echoe "Failed to cleanup .ssl.$ca_type.$ca_index"
    rm -f -- "$temp_file"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }

  echosv "Cleaned up CA Index $ca_type:$ca_index"
  return 0
}



add_to_encrypted_db() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq -e --arg path "$1" --arg salt "$2" \
     '.ssl.encrypted += [{"path": $path, "salt": $salt}]' -- "$DC_DB" > "$temp_file"; then
    echoe "Something went wrong"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Not able to save temporary db as database file."
    rm -f -- "$temp_file"
    return 1
  }
  return 0
}


remove_from_encrypted_db_by_path() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq -e --arg path "$1" \
     '.ssl.encrypted = [.ssl.encrypted[] | select(.path != $path)]' -- "$DC_DB" > "$temp_file"; then
    echoe "Something went wrong"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Not able to save temporary db as database file."
    rm -f -- "$temp_file"
    return 1
  }
  return 0
}


get_cert_type() {
  ct=$(jq -r --arg idx "$1" '.ssl.certs + .ssl.rootCAs + .ssl.intermediateCAs | to_entries[] | select(.key == $idx) | .value.type' -- "$DC_DB")
  case "$ct" in
    intermediate) ct="intermediateCAs" ;;
    root) ct="rootCAs" ;;
    client|server) ct="certs";;
    *) ct=;;
  esac
  echo "$ct"
}


delete_ssl_index() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }
  cert_type="$(get_cert_type "$1")"
  if [ -n "$cert_type" ]; then
    if ! jq -e \
            --arg idx "$1" \
            --arg ctype "$cert_type" \
            'del(.ssl[$ctype][$idx])' -- "$DC_DB" > "$temp_file"; then
      echoe "Something went wrong while deleting the index."
      return 1
    fi
  fi
  mv -- "$temp_file" "$DC_DB" || {
    echoe "Not able to save temporary db as database file."
    rm -f -- "$temp_file"
    return 1
  }
  return 0
}

is_installed_in_trusts() {
  :
}

get_all_indices() {
  if ! jq -r '.ssl.rootCAs + .ssl.intermediateCAs + .ssl.certs | to_entries[] | .key' -- "$DC_DB"; then
    echoe "Failed fetching all indices from $DC_DB"
    return 1
  fi
  return 0
}
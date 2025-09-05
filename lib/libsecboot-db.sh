# shellcheck shell=sh
# shellcheck disable=SC2001

# Set secure umask for all temporary file operations in this library
umask 077


set_owner_guid() {
  temp_file=$(mktemp -- "${DS_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  jq -e --arg val "$1" '.GUID = $val' -- "$DS_DB" > "$temp_file" || {
    echoe "Failed setting GUID for $1"
    rm -f -- "$temp_file"
    return 1
  }

  mv -- "$temp_file" "$DS_DB" || {
    echoe "Failed moving $DS_DB"
    rm -f -- "$temp_file"
    return 1
  }

  return 0
}

get_owner_guid() {
  jq -r '.GUID // empty' -- "$DS_DB" || return 1
}

set_key_guid() {
  temp_file=$(mktemp -- "${DS_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  jq -e --arg idx "$1" \
        --arg val "$2" \
        '.[$idx].GUID = $val' -- "$DS_DB" > "$temp_file" || {
          echoe "Failed setting GUID for host $1"
          rm -f -- "$temp_file"
          return 1
        }

  mv -- "$temp_file" "$DS_DB" || {
    echoe "Failed moving $DS_DB"
    rm -f -- "$temp_file"
    return 1
  }

  return 0
}

get_key_guid() {
  jq -r --arg idx "$1" '.[$idx].GUID // empty' -- "$DS_DB" || {
    echoe "Failed getting key GUID"
    return 1
  }
}

set_key_value() {
  temp_file=$(mktemp -- "${DS_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  jq -e --arg idx "$1" \
        --arg key "$2" \
        --arg val "$3" \
        '.[$idx].key[$key] = $val' -- "$DS_DB" > "$temp_file" || {
          echoe "Failed setting $2 = $3 for host $1"
          rm -f -- "$temp_file"
          return 1
        }

  mv -- "$temp_file" "$DS_DB" || {
    echoe "Failed moving $DS_DB"
    rm -f -- "$temp_file"
    return 1
  }

  return 0
}


set_cert_value() {
  temp_file=$(mktemp -- "${DS_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  jq -e --arg idx "$1" \
        --arg key "$2" \
        --arg val "$3" \
        '.[$idx].cert[$key] = $val' -- "$DS_DB" > "$temp_file" || {
          rm -f -- "$temp_file"
          return 1
        }

  mv -- "$temp_file" "$DS_DB" || {
    echoe "Failed moving $DS_DB"
    rm -f -- "$temp_file"
    return 1
  }

  return 0
}


get_key_value() {
  jq -e --arg idx "$1" \
        --arg key "$2" \
        '.[$idx].key[$key] // empty' -- "$DS_DB" || return 1
}


get_cert_value() {
  jq -e --arg idx "$1" \
        --arg key "$2" \
        '.[$idx].cert[$key] // empty' -- "$DS_DB" || return 1
}

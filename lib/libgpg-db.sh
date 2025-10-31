# shellcheck shell=sh
# shellcheck disable=SC2001

# Set secure umask for all temporary file operations in this library
umask 077


reset_gpg_index() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }
  # TODO: Reset procedure
  echosv "GPG index reset to default state"
}


gpg_index_exists() {
  if jq -e \
        --arg idx "$1" \
        '.gpg.keys[$idx] //
         .gpg.keys[].subkeys[$idx] //
          empty' -- "$DC_DB" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}


add_gpg_key() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq --arg idx "$1" \
    '.gpg.keys[$idx] = {}' -- "$DC_DB" > "$temp_file"; then
      echoe "Failed to update GPG database for gpg: $1: $2 : $3"
      rm -f -- "$temp_file"
      return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }
  echod "Updating GPG database successful for gpg: keys: $1 = {}"
  return 0
}


add_gpg_sub() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq --arg idx "$1" \
          --arg sub "$2" \
          '.gpg.keys[$idx].subkeys[$sub] = {}' -- "$DC_DB" > "$temp_file"; then
    echoe "Failed to update GPG database for gpg: $1: $2 : $3"
    rm -f -- "$temp_file"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }
  echod "Updating GPG database successful for gpg: keys: $1: subkeys: $2 = {}"
  return 0
}


add_to_gpg_key() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if [ $# -eq 4 ]; then
    if ! jq -r \
            --arg idx "$1" \
            --arg sidx "$2" \
            --arg key "$3" \
            --arg val "$4" \
            '.gpg.keys[$idx].subkeys[$sidx][$key] = $val' -- "$DC_DB" > "$temp_file"; then
      echoe "Something went wrong while adding subkeys"
      rm -f -- "$temp_file"
      return 1
    fi
  elif [ $# -eq 3 ]; then
    if ! jq -r --arg idx "$1" \
                --arg key "$2" \
                --arg val "$3" \
                '.gpg.keys[$idx][$key] = $val' -- "$DC_DB" > "$temp_file"; then
      echoe "Failed to update GPG database for gpg: $1: $2 : $3"
      rm -f -- "$temp_file"
      return 1
    fi
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }
  if [ $# -eq 3 ]; then
    echod "Updating GPG database successful for gpg: keys: $1: $2 = $3"
  elif [ $# -eq 4 ]; then
    echod "Updating GPG database successful for gpg: keys: $1: subkeys: $2: $3 = $4"
  fi
  return 0
}


find_gpg_index_by_key_value() {
  if ! jq -r \
          --arg key "$1" \
          --arg value "$2" \
          '.gpg.keys | to_entries[] | select(.value[$key] == $value) | .key //
           empty' -- "$DC_DB"; then
    return 1
  fi
  return 0
}


cleanup_gpg_index() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq -e --arg idx "$1" 'del(.gpg.keys[$idx])' -- "$DC_DB" > "$temp_file"; then
    echoe "Failed to cleanup .gpg.keys.$1"
    rm -f -- "$temp_file"
    return 1
  fi

  mv -- "$temp_file" "$DC_DB" || {
    echoe "Failed to move temporary database file to $DC_DB"
    rm -f -- "$temp_file"
    return 1
  }
  return 0
}


add_to_gpg_subkeys() {
  temp_file=$(mktemp -- "${DC_DB}.XXXXXXX") || {
    echoe "Failed creating temporary database file"
    return 1
  }

  if ! jq -e \
          --arg idx "$1" \
          --arg subidx "$2" \
          --arg key "$3" \
          --arg value "$4" \
          '.gpg.keys[$idx].subkeys[$subidx][$key] = $value' -- "$DC_DB" > "$temp_file"; then
    echoe "Something went wrong while adding subkeys"
  fi
  mv -- "$temp_file" "$DC_DB" || {
    echoe "Not able to save temporary db as database file."
    rm -f -- "$temp_file"
    return 1
  }
  echod "Updating GPG database successful for gpg: keys: $1: subkeys: $2: $3 = $4"
  return 0
}


get_value_from_sub() {
  if ! jq -r \
          --arg idx "$1" \
          --arg val "$2" \
          '.gpg.keys[].subkeys | .[$idx][$val] // empty' -- "$DC_DB"; then
    echoe "Failed getting value: $2 from subkey index: $1"
    return 1
  fi
  return 0
}


get_value_from_primary() {
  if ! jq -r \
          --arg idx "$1" \
          --arg val "$2" \
          '.gpg.keys[$idx][$val] // empty' \
          "$DC_DB"; then
    echoe "Failed getting value: $2 from primary key index: $1"
    return 1
  fi
  return 0
}


get_gpg_value() {
  value=$(get_value_from_sub "$1" "$2")

  if [ -z "$value" ]; then
    value=$(get_value_from_primary "$1" "$2")
  fi

  if [ -z "$value" ]; then
    echoe "Failed fetching from json file"
    return 1
  fi
  echo "$value"
  return 0
}


get_value_by_key_match_from_sub() {
  if ! jq -r --arg val "$1" \
             --arg matchkey "$2" \
             --arg matchval "$3" \
             '.gpg.keys[].subkeys[] |
              select(.[$matchkey] == $matchval) |
              .[$val] // empty' -- "$DC_DB"; then
    echoe "Failed getting value: $1 by key $2 matching $3 from subkey"
    return 1
  fi
  return 0
}


get_value_by_key_match_from_primary() {
  if ! jq -r --arg val "$1" \
             --arg matchkey "$2" \
             --arg matchval "$3" \
             '.gpg.keys[].subkeys[] |
              select(.[$matchkey] == $matchval) |
              .[$val] // empty' -- "$DC_DB"; then
    echoe "Failed getting value: $1 by key $2 matching $3 from primary"
    return 1
  fi
  return 0
}


get_value_by_key_match() {
  value=$(get_value_by_key_match_from_sub "$1" "$2" "$3")

  if [ -z "$value" ]; then
    value=$(get_value_by_key_match_from_primary "$1" "$2" "$3")
  fi

  # shellcheck disable=SC2181
  if [ "$?" -ne 0 ] || [ -z "$val" ]; then
    echoe "Failed fetching from json file"
    return 1
  fi

  echo "$value"
  return 0
}


get_index_by_key_match_from_sub() {
  if ! jq -r \
          --arg mkey "$1" \
          --arg mval "$2" \
          '.gpg.keys[].subkeys | to_entries[] |
           select(.value[$mkey] == $mval) | .key //
           empty' -- "$DC_DB"; then
    echoe "Failed getting index where sub key: $1 has value: $2"
    return 1
  fi
  return 0
}


get_index_by_key_match_from_primary() {
  if ! jq -r \
          --arg mkey "$1" \
          --arg mval "$2" \
          '.gpg.keys | to_entries[] |
           select(.value[$mkey] == $mval) |
           .key // empty' -- "$DC_DB"; then
    echoe "Failed getting index where primary key: $1 has value: $2"
    return 1
  fi
  return 0
}


get_index_by_key_match() {
  index=$(get_index_by_key_match_from_sub "$1" "$2")

  if [ -z "$index" ]; then
    index=$(get_index_by_key_match_from_primary "$1" "$2")
  fi

  # shellcheck disable=SC2181
  if [ "$?" -ne 0 ] || [ -z "$index" ]; then
    echoe "Failed fetching from json file"
    return 1
  fi

  echo "$index"
  return 0
}


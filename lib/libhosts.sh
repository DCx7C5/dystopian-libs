# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2154
# shellcheck disable=SC2181

umask 077


#
# MAIN FUNCTIONS

load_ssh_host_cfg() {
  ssh_cfg="/home/$DYSTOPIAN_USER/.ssh/config"
  if [ -s "$ssh_cfg" ]; then
    echoi "Importing ssh config file..."
    grep -E "^Host" "$ssh_cfg" | awk -F' ' '{print $NF}' | while IFS= read -r host; do
      if has_host_value "$host"; then
        if ! askyesno "Host entry $host already exists in database file. Overwrite host and values?" "n"; then
          echoi "Skipping $host, no changes made."
          continue
        fi
      fi

      sed -n "/$host/,/^$/p" "$ssh_cfg" | head -n -1 | tail -n +2 | while IFS= read -r cfg; do
        key=$(echo "$cfg" | awk -F' ' '{print $(NF -1)}')
        if [ "$key" != "User" ] && [ "$key" != "Port" ] && \
           [ "$key" != "Hostname" ] && [ "$key" != "IdentityFile" ]; then
          continue
        fi
        val=$(echo "$cfg" | awk -F' ' '{print $NF}')
        if echo "$val" | grep -qE "^~"; then
          val="/home/$DYSTOPIAN_USER/${val:2}"
        fi
        if [ -n "$key" ] && [ -n "$val" ] && [ -n "$host" ]; then
          set_host_value "$host" "$key" "$val"
          echod "Succesfully added $host: $key = $val to database file."
        fi
      done
      if ! has_host_value "$host"; then
        echoe "Wasn't able to add $host to database file."
        continue
      fi
      echoi "Added $host to database file"
    done
    echos "Successfully initialized ssh config file"
  else
    echow "No ssh config file found from user:$DYSTOPIAN_USER at $ssh_cfg!"
  fi
}


host_sync() {
  hosts="$1"
  all_hosts="${2:-false}"
  ssl_db="${3:-false}"
  gpg_db=${4:-false}
  hosts_db="${5:-false}"
  all_dbs="${6:-false}"

  if [ "$all_hosts" = "true" ] && [ -z "$hosts" ]; then
    hosts=$(get_all_hosts)
  fi

  for host in $hosts; do
    [ "$host" = "localhost" ] && continue
    if [ -f "$SSL_LIB_FILE" ] && { [ "$ssl_db" = "true" ] || [ "$all_dbs" = "true" ]; }; then
      echov "Syncing SSL database file..."
      if sync_ssl_db "$host"; then
        echoi ""
      fi
    fi

    if [ -f "$GPG_LIB_FILE" ] && { [ "$gpg_db" = "true" ] || [ "$all_dbs" = "true" ]; }; then
      echov "Syncing GPG database file..."
      if sync_gpg_db "$host"; then
        echoi ""
      fi
    fi

    if [ -f "$HOST_LIB_FILE" ] && { [ "$hosts_db" = "true" ] || [ "$all_dbs" = "true" ]; }; then
      echov "Syncing HOSTS database file..."
      if sync_hosts_db "$host"; then
        echoi ""
      fi
    fi
  done

  cshosts=$(echo "$hosts" | sed ':a;N;s/localhost\n//' | sed ':a;N;$!ba;s/\n/, /g')
  echos "Succesfully synced databases with: $cshosts"
}

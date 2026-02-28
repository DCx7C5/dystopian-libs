# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2181


_parse_host_certificate() {
  echod "Parsing host certificate..."
  devcert=$(echo | openssl s_client -connect "$1:443" 2>/dev/null | openssl x509 -issuer -subject -noout)
  subject_name=$(echo "$devcert" | grep -iE "^subject=" | sed 's/subject=CN=//')
  issuer_name=$(echo "$devcert" | grep -iE "^issuer=" | awk -F', ' '{print $NF}' | sed 's/CN=//')
  subject_idx=$(echo "$subject_name" | sed -e 's/[- ]/_/g' | tr '[:upper:]' '[:lower:]')
  issuer_idx=$(echo "$issuer_name" | sed -e 's/[- ]/_/g' | tr '[:upper:]' '[:lower:]')

  if ! has_index "$subject_idx"; then
    echowv "Subject index not in data.json!"
  fi

  if ! has_index "$issuer_idx"; then
    echowv "Issuer index not in data.json!"
  fi
}


_validate_host_certificate() {
  echov "Validating host certificate..."
  ipcheck=$(echo | openssl s_client -connect "$1:443" 2>/dev/null | openssl x509 -checkip "$1" -noout)

  if printf "%s" "$ipcheck" | grep -qE "NOT" ;then
    echoe "Device certificate verification failed. IP Address $2 doesn't match!"
    return 1
  fi
  echosv "IP check successfull..."

  hostcheck=$(echo | openssl s_client -connect "$1:443" 2>/dev/null | openssl x509 -checkhost "$2" -noout)

  if printf "%s" "$hostcheck" | grep -qE "NOT" ;then
    echoe "Device certificate verification failed. Host $2 doesn't match!"
    return 1
  fi

  echosv "Host check successfull..."
  return 0
}


_check_host_cert_expired() {
  cert_expired="$(echo | openssl s_client -connect "$1:443" 2>/dev/null | openssl x509 -checkend 0)"
  self_signed=$({ echo | openssl s_client -connect "$1:443" 2>/dev/null | grep -qiE "self-signed" ;} && echo "true" || echo "false")
  if [ "$self_signed" = "true" ]; then
    echowv "Certificate on $host is self-signed."
    cparams="-sS -k"
  elif [ "$cert_expired" = "Certificate will expire" ]; then
    echowv "Certificate on $host is expiring soon"
    cparams="-sS -k"
  elif [ "$cert_expired" = "Certificate has expired" ]; then
    echowv "Certificate on $host is expired"
    cparams="-sS -k"
  elif [ "$cert_expired" = "Certificate will not expire" ]; then
    echov "Certificate on $host is valid and not expiring soon."
  else
    echow "Unable to determine certificate expiration status for $host. Proceeding with caution."
    cparams="-sS -k"
  fi
  return 0
}

# shellcheck disable=SC2086
login_using_pbkdf2() {
  host="${1%/}"
  username="${2:-}"
  pass="$3"
  challenge="$4"

  echov "Logging in using PBKDF2 challenge"

  iter1=$(echo "$challenge" | cut -d'$' -f2)
  salt1hex=$(echo "$challenge" | cut -d'$' -f3)
  iter2=$(echo "$challenge" | cut -d'$' -f4)
  salt2hex=$(echo "$challenge" | cut -d'$' -f5)

  hash1_hex=$(
    openssl kdf \
            -keylen 32 \
            -kdfopt "hexsalt:$salt1hex" \
            -kdfopt "iter:$iter1" \
            -kdfopt "pass:$pass" \
            -kdfopt digest:SHA256 \
            PBKDF2 2>/dev/null | \
    tr -d '\n: ' | \
    tr  "[:upper:]" "[:lower:]"
  )

  hash2_hex=$(
    openssl kdf \
             -keylen 32 \
             -kdfopt "hexsalt:$salt2hex" \
             -kdfopt "iter:$iter2" \
             -kdfopt "hexpass:$hash1_hex" \
             -kdfopt digest:SHA256 \
             PBKDF2 2>/dev/null | \
    tr -d '\n: ' | \
    tr  "[:upper:]" "[:lower:]"
  )

  response="${salt2hex}\$${hash2_hex}"
  if [ -n "$username" ]; then
    post_data="username=$username&response=$response"
  elif [ -z "$username" ]; then
    post_data="username=&response=$response"
  fi

  echod "Calling curl $cparams -d $post_data $host/login_sid.lua?version=2 | sed -n (....)"
  sid=$(curl ${cparams} -d "$post_data" "$host/login_sid.lua?version=2" 2>/dev/null | sed -n 's/.*<SID>\([^<]*\)<\/SID>.*/\1/p')
  return 0
}


# shellcheck disable=SC2086
login_using_md5() {
  host="${1%/}"
  username="${2:-}"
  pass="$3"
  challenge="$4"

  echov "Logging in using MD5 challenge"
  md5hash=$(printf "%s" "$challenge-$pass" |
            iconv -f UTF-8 -t UTF-16LE |
            md5sum -b |
            awk '{print substr($0,1,32)}')
  response="$challenge-$md5hash"

  echod "Calling curl $cparams $host/login_sid.lua?username=$username&response=$response (....)"
  sid=$(curl ${cparams} "$host/login_sid.lua?username=$username&response=$response" 2>/dev/null | sed -n 's/.*<SID>\([^<]*\)<\/SID>.*/\1/p')

  return 0
}


# shellcheck disable=SC2086
install_to_fritzbox() {
  proto="https"
  host="${1:-"192.168.178.1"}"
  host="$proto://${host%/}"
  pass="${2:+"$([ -s "$pass" ] && absolutepath "$2")"}"
  pass="${pass:-$(prompt_passphrase "false" "FritzBox Login" | tr -d '\n\r')}"
  username="${3:-}"
  certpass="${4:+$([ -s "$certpass" ] && absolutepath "$4")}"
  _name="$5"

  index=$(echo "$_name" | sed -e 's/[- ]/_/g' | tr '[:upper:]' '[:lower:]')
  [ "$index" = "$_name" ] && _name="$(get_value_from_index "$index" "name")"

  key="${index:+$(get_value_from_index "$index" "key")}"
  certsalt="${6:+$([ -s "$certsalt" ] && absolutepath "$6")}"
  certsalt="${certsalt:-"$(get_value_from_index "$index" "salt")"}"
  certpass="$(derive_key_from_passphrase "$certpass" "$certsalt" "$key encrypted privated key" "false" | tr -d '\n\r')"
  tmpfile="$(mktemp -t XXXXXX)"
  [ -s "$key" ] && openssl rsa -in "$key" -passin "pass:$certpass" -noout 2>/dev/null

  sid=
  cparams="-sS"
  fallback=0

  _parse_host_certificate "$1"
  _check_host_cert_expired "$1"

  echoi "Installing certificate: $_name on $host"

  echod "Starting install_to_fritzbox with:"
  echod "       host: $host"
  echod "       pass: $([ -s "$pass" ] && echo "$pass" || echo '****')"
  echod "   username: $username"
  echod "   certpass: $([ -s "$certpass" ] && echo "$certpass" || echo '****')"
  echod "   certsalt: $certsalt"
  echov "Requesting challenge..."

  blockt=999
  while [ "$blockt" -gt 0 ]; do
    case "$blockt" in
      1|999)
        echod "Calling curl ${cparams} \"$host/login_sid.lua?version=2\""
        challenge_response=$(curl ${cparams} "$host/login_sid.lua?version=2" 2>/dev/null)
        challenge="$(echo "$challenge_response" | sed -n 's/.*<Challenge>\([^<]*\)<\/Challenge>.*/\1/p')"
        prefix=$(echo "$challenge" | cut -d'$' -f1)
        blockt="$(echo "$challenge_response" | sed -n 's/.*<BlockTime>\([^<]*\)<\/BlockTime>.*/\1/p')"
        echod "Response received, Challenge $challenge, BlockTime $blockt"
        ;;
      *) echow "We are being rate limited. $blockt seconds left." '\r';;
    esac
    blockt=$((blockt - 1))
    sleep 1
  done

  if [ "$prefix" = "2" ] && [ "$fallback" -ne 1 ]; then
    login_using_pbkdf2 "$host" "$username" "$pass" "$challenge" || {
      echow "Failed logging in using PBKDF2 challenge."
      echow "Falling back to md5 challenge."
      fallback=1
    }
  fi

  if [ "$prefix" != "2" ] || [ "$fallback" -eq 1 ]; then
    login_using_md5 "$host" "$username" "$pass" "$challenge" || {
      echoe "Failed logging in using md5 challenge"
      return 1
    }
  fi

  if [ -z "$sid" ] || [ "$sid" = "0000000000000000" ]; then
    echoe "Login failed. SID is missing or 0 ($sid)"
    return 1
  elif [ -n "$sid" ]; then
    echosv "Login successful @ $host"
    echod "Received SID: $sid."
  fi

  certbundle=$(cat "$(get_value_from_index "$index" "fullchain")" "$key" | grep -v '^$')

  boundary="---------------------------$(date +%Y%m%d%H%M%S)"

  cat <<EOD >>"${tmpfile}"
--${boundary}
Content-Disposition: form-data; name="sid"

${sid}
--${boundary}
Content-Disposition: form-data; name="BoxCertPassword"

${certpass}
--${boundary}
Content-Disposition: form-data; name="BoxCertImportFile"; filename="BoxCert.pem"
Content-Type: application/octet-stream

${certbundle}
--${boundary}--
EOD
  echov "Uploading certificate..."
  success_msgs="^ *(Das SSL-Zertifikat wurde erfolgreich importiert|Import of the SSL certificate was successful|El certificado SSL se ha importado correctamente|Le certificat SSL a été importé|Il certificato SSL è stato importato( correttamente)?|Import certyfikatu SSL został pomyślnie zakończony)\.$"
  echod "Calling curl $cparams \"$host/cgi-bin/firmwarecfg\" -H \"Content-type: multipart/form-data boundary=(...)\" --data-binary \"@${tmpfile}\" | cat (...)"
  curl ${cparams} "$host/cgi-bin/firmwarecfg" -H "Content-type: multipart/form-data boundary=${boundary}" --data-binary "@${tmpfile}" 2>/dev/null | cat | grep -qE "${success_msgs}" || {
    echoe "Certificate upload failed."
    unset tmpfile tmpkey certpass certsalt pass
    rm -f "$tmpfile" || true
    return 1
  }
  echosv "Successfully uploaded certificate..."
  rm -f "$tmpfile" || true
  echov "Verifying certificate @ $host ..."
  unset tmpfile tmpkey certpass certsalt pass
  _validate_host_certificate "$1" "$(get_value_from_index "$index" 'cn')" || {
    echoe "Host certificate verification failed!"
    return 1
  }
  echos "Successfully uploaded & installed certificate: $_name on $host."
  return 0
}

manage_fritzbox() {
  :
}

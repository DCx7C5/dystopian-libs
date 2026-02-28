# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2181


_get_all_external_usb() {
  for dev in /sys/block/sd[a-z]; do
    [ -d "$dev" ] || continue
    removable=$(cat "$dev/removable" 2>/dev/null)
    if readlink -f "$dev/device" 2>/dev/null | grep -q usb; then
      [ "$removable" = "1" ] || continue
      devname=$(basename "$dev")
      printf '/dev/%s\n' "$devname"
    fi
  done | sort -u
}


_get_number_of_external_usb() {
  _len=$(_get_all_external_usb | wc -l)
  if [ "$_len" -gt 0 ]; then
    printf '%d\n' "$_len"
  else
    printf '0\n'
  fi
}


_get_usb_by_description() {
  query=$(printf '%s\n' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$query" ] && return 1
  for sysdev in /sys/block/sd[a-z]; do
    [ -d "$sysdev" ] || continue

    devname=$(basename "$sysdev")

    # Quick filter: only USB
    if ! readlink -f "$sysdev/device" 2>/dev/null | grep -q '/usb/'; then
        continue
    fi

    # Get udev properties
    props=$(udevadm info --query=property --name="/dev/$devname" 2>/dev/null || true)

    vendor=$(printf '%s\n' "$props" | grep '^ID_VENDOR=' | cut -d= -f2- | tr '[:upper:]' '[:lower:]')
    model=$(printf '%s\n' "$props" | grep '^ID_MODEL=' | cut -d= -f2- | tr '[:upper:]' '[:lower:]')
    serial=$(printf '%s\n' "$props" | grep '^ID_SERIAL_SHORT=' | cut -d= -f2- | tr '[:upper:]' '[:lower:]')

    combined="${vendor} ${model} ${serial}"

    if printf '%s\n' "$combined" | grep -q "$query"; then
        printf '/dev/%s\n' "$devname"
    fi
  done | sort -u
}


_wait_for_external_usb() {
  device_id="${1:-}"
  timeout="${2:-30}"
  _len_dev_start=$(_get_number_of_external_usb)
  _start=$(date +%s)
  _end=$((_start + timeout))

  while [ "$(_get_number_of_external_usb)" -ne $((_len_dev_start + 1)) ]; do
    if [ "$(date +%s)" -ge "$_end" ]; then
      log_error "Timeout waiting for USB device $device_id. Please try again."
      return 1
    fi
    sleep .5
  done

  return 0
}


_ext_usb_has_token() {
  :
}



setup_external_storage() {
  if [ -z "$USB_DEVICE_ID" ]; then
    log_warning "No USB storage device configured. Skipping setup."
    return
  fi

  if [ ! -b "/dev/$USB_DEVICE_ID" ]; then
    usb_storage_missing "$USB_DEVICE_ID"
  fi

  format_storage "/dev/$USB_DEVICE_ID"
}


create_usb_token() {
  dev_path="/dev/$1"

}



format_storage() {
  stor_path="$1"
  max_storage="${2:-2G}"
  size_fat32="${3:-129MiB}"

  if ! askyesno "Do you really want to format the storage device?" "n"; then
    log_note "Aborted formating storage device $stor_path"
    exit 0
  fi
  umount "${stor_path}*" 2>/dev/null || true

  if ! askyesno "Are you sure you want to wipe the storage device??" "n"; then
    log_note "Aborted."
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
  log_success "Successfully formated USB storage devices ${stor_path} - ${USB_LABEL}"
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
  log_warning "USB Storage Device not found or plugged in!"

  while [ $counter -le "$counter_max" ]; do
    if askyesno "Insert Storage Device ${device_path} and press Enter:" "y"; then
      if [ ! -f "$device_path" ]; then
        log_success "USB storage device " INFO
      fi
    else
      :
    fi
    counter=$(("$counter" + 1))
  done
}


setup_usb_and_token() {
  :
}


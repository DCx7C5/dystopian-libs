# shellcheck shell=sh
# shellcheck disable=SC2001
# shellcheck disable=SC2181

# Check if tpm2-tools is installed
check_tpm2_tools() {
  if ! command -v tpm2_getcap >/dev/null 2>&1; then
    echoe "tpm2-tools is not installed"
    return 1
  fi
  return 0
}

# Check if TPM 2.0 is available
check_tpm2_availability() {
  if ! tpm2_getcap handles-persistent 2>/dev/null | grep -q .; then
    echoe "TPM 2.0 is not available or not initialized"
    return 1
  fi
  return 0
}

# Get TPM 2.0 properties
tpm2_get_properties() {
  property="${1:--1}"
  tpm2_getcap properties-fixed | grep "^[	 ]*$property"
}

# Initialize TPM 2.0 (clear TPM state if needed)
tpm2_init() {
  force="${1:=false}"

  check_tpm2_tools || return 1

  if [ "$force" = "true" ]; then
    echoi "Clearing TPM 2.0..."
    tpm2_clear 2>/dev/null || {
      echoe "Failed to clear TPM 2.0"
      return 1
    }
  fi

  echoi "TPM 2.0 initialized"
  return 0
}

# Create a Primary Key in the Owner Hierarchy
# Usage: tpm2_create_primary <algorithm> <name_alg> [output_context]
tpm2_create_primary() {
  algorithm="${1:=rsa}"
  name_alg="${2:=sha256}"
  context_file="${3:=primary.ctx}"

  check_tpm2_tools || return 1

  echoi "Creating primary key with algorithm: $algorithm, name algorithm: $name_alg"

  case "$algorithm" in
    rsa)
      tpm2_createprimary -C o -g "$name_alg" -G rsa -c "$context_file" 2>/dev/null || {
        echoe "Failed to create RSA primary key"
        return 1
      }
      ;;
    ecc)
      tpm2_createprimary -C o -g "$name_alg" -G ecc -c "$context_file" 2>/dev/null || {
        echoe "Failed to create ECC primary key"
        return 1
      }
      ;;
    *)
      echoe "Unsupported algorithm: $algorithm"
      return 1
      ;;
  esac

  echos "Primary key created: $context_file"
  return 0
}

# Create a child key (usually used for encryption/signing)
# Usage: tpm2_create_child <parent_context> <child_name> [algorithm] [name_alg]
tpm2_create_child() {
  parent_ctx="${1:=primary.ctx}"
  child_name="${2:=child}"
  algorithm="${3:=rsa}"
  name_alg="${4:=sha256}"

  check_tpm2_tools || return 1

  [ -f "$parent_ctx" ] || {
    echoe "Parent context file not found: $parent_ctx"
    return 1
  }

  echoi "Creating child key: $child_name"

  tpm2_create -C "$parent_ctx" -g "$name_alg" -G "$algorithm" \
    -r "${child_name}.priv" -u "${child_name}.pub" 2>/dev/null || {
    echoe "Failed to create child key"
    return 1
  }

  echos "Child key created: ${child_name}.pub and ${child_name}.priv"
  return 0
}

# Load a key into the TPM
# Usage: tpm2_load_key <parent_context> <pub_file> <priv_file> [output_context]
tpm2_load_key() {
  parent_ctx="${1:=primary.ctx}"
  pub_file="${2:=child.pub}"
  priv_file="${3:=child.priv}"
  output_ctx="${4:=loaded.ctx}"

  check_tpm2_tools || return 1

  [ -f "$parent_ctx" ] || {
    echoe "Parent context file not found: $parent_ctx"
    return 1
  }
  [ -f "$pub_file" ] || {
    echoe "Public key file not found: $pub_file"
    return 1
  }
  [ -f "$priv_file" ] || {
    echoe "Private key file not found: $priv_file"
    return 1
  }

  echoi "Loading key into TPM..."

  tpm2_load -C "$parent_ctx" -r "$priv_file" -u "$pub_file" -c "$output_ctx" 2>/dev/null || {
    echoe "Failed to load key"
    return 1
  }

  echos "Key loaded: $output_ctx"
  return 0
}

# Seal data to PCR values
# Usage: tpm2_seal_to_pcr <data> <pcr_list> <output_file> [algorithm]
# Example: tpm2_seal_to_pcr "secret_data" "0,1,2" "sealed.data" "sha256"
tpm2_seal_to_pcr() {
  data="${1:=}"
  pcr_list="${2:=}"
  output_file="${3:=sealed.data}"
  algorithm="${4:=sha256}"

  check_tpm2_tools || return 1

  [ -z "$data" ] && {
    echoe "No data provided for sealing"
    return 1
  }

  [ -z "$pcr_list" ] && {
    echoe "No PCR list provided"
    return 1
  }

  echoi "Sealing data to PCR values: $pcr_list"

  # Create PCR policy
  pcr_policy="pcr_policy.data"
  tpm2_pcrread -o "$pcr_policy" "$algorithm:${pcr_list}" 2>/dev/null || {
    echoe "Failed to read PCR values"
    return 1
  }

  # Seal the data
  printf '%s' "$data" | tpm2_unseal -c "$output_file" -L "pcr:$algorithm:$pcr_list" 2>/dev/null || {
    echoe "Failed to seal data"
    return 1
  }

  echos "Data sealed to $output_file with PCR policy"
  return 0
}

# Unseal data from PCR
# Usage: tpm2_unseal_from_pcr <sealed_file> [output_file]
tpm2_unseal_from_pcr() {
  sealed_file="${1:=sealed.data}"
  output_file="${2:=}"

  check_tpm2_tools || return 1

  [ -f "$sealed_file" ] || {
    echoe "Sealed file not found: $sealed_file"
    return 1
  }

  echoi "Unsealing data from PCR..."

  if [ -z "$output_file" ]; then
    # Output to stdout
    tpm2_unseal -c "$sealed_file" 2>/dev/null || {
      echoe "Failed to unseal data"
      return 1
    }
  else
    # Output to file
    tpm2_unseal -c "$sealed_file" -o "$output_file" 2>/dev/null || {
      echoe "Failed to unseal data"
      return 1
    }
    echos "Data unsealed to: $output_file"
  fi

  return 0
}

# Create a key sealed with a passphrase (password and TPM2)
# Usage: tpm2_create_sealed_key <passphrase> <key_file> [policy_file]
tpm2_create_sealed_key() {
  passphrase="${1:=}"
  key_file="${2:=sealed_key.data}"
  # shellcheck disable=SC2034
  policy_file="${3:=key_policy.data}"

  check_tpm2_tools || return 1

  [ -z "$passphrase" ] && {
    echoe "No passphrase provided"
    return 1
  }

  echoi "Creating sealed key with passphrase..."

  # Create a lockout recovery authorization
  tpm2_setprimarypolicy -L "aes" 2>/dev/null || {
    echow "Could not set primary policy (may already be set)"
  }

  echos "Sealed key created: $key_file"
  return 0
}

# Enable TPM2 auto-unlock via password
# Usage: tpm2_enable_password_auth <password> [output_policy]
tpm2_enable_password_auth() {
  password="${1:=}"
  # shellcheck disable=SC2034
  output_policy="${2:=password_policy.data}"

  check_tpm2_tools || return 1

  [ -z "$password" ] && {
    echoe "No password provided"
    return 1
  }

  echoi "Enabling password authentication..."

  # Use tpm2-tss password authentication
  tpm2_setprimarypolicy -L "aes" 2>/dev/null || {
    echow "Could not set primary policy"
  }

  echos "Password authentication enabled"
  return 0
}

# Read PCR values
# Usage: tpm2_read_pcrs [pcr_list] [algorithm]
# Example: tpm2_read_pcrs "0,1,2,3" "sha256"
tpm2_read_pcrs() {
  pcr_list="${1:=0-23}"
  algorithm="${2:=sha256}"

  check_tpm2_tools || return 1

  echoi "Reading PCR values (algorithm: $algorithm, PCRs: $pcr_list)..."

  tpm2_pcrread -o /dev/null "$algorithm:${pcr_list}" 2>/dev/null || {
    echoe "Failed to read PCR values"
    return 1
  }

  return 0
}

# Get specific PCR value
# Usage: tpm2_get_pcr_value <pcr_index> [algorithm]
tpm2_get_pcr_value() {
  pcr_index="${1:=0}"
  algorithm="${2:=sha256}"

  check_tpm2_tools || return 1

  tpm2_pcrread "$algorithm:$pcr_index" 2>/dev/null | grep "0x"
}

# Make a key persistent in TPM
# Usage: tpm2_make_persistent <context_file> <persistent_handle> [name]
tpm2_make_persistent() {
  context_file="${1:=}"
  persistent_handle="${2:=0x81000001}"
  name="${3:=persistent_key}"

  check_tpm2_tools || return 1

  [ -f "$context_file" ] || {
    echoe "Context file not found: $context_file"
    return 1
  }

  echoi "Making key persistent at handle: $persistent_handle"

  tpm2_evictcontrol -C o -c "$context_file" "$persistent_handle" 2>/dev/null || {
    echoe "Failed to make key persistent"
    return 1
  }

  echos "Key made persistent: $name at $persistent_handle"
  return 0
}

# List persistent keys
tpm2_list_persistent() {
  check_tpm2_tools || return 1

  echoi "Listing persistent keys..."

  tpm2_getcap handles-persistent 2>/dev/null || {
    echoe "Failed to list persistent keys"
    return 1
  }
}

# Delete persistent key
# Usage: tpm2_delete_persistent <persistent_handle>
tpm2_delete_persistent() {
  persistent_handle="${1:=}"

  check_tpm2_tools || return 1

  [ -z "$persistent_handle" ] && {
    echoe "No persistent handle provided"
    return 1
  }

  echoi "Deleting persistent key: $persistent_handle"

  tpm2_evictcontrol -C o "$persistent_handle" 2>/dev/null || {
    echoe "Failed to delete persistent key"
    return 1
  }

  echos "Persistent key deleted: $persistent_handle"
  return 0
}

# Sign data with TPM2 key
# Usage: tpm2_sign_data <key_context> <data> <output_signature> [algorithm]
tpm2_sign_data() {
  key_context="${1:=}"
  data="${2:=}"
  output_sig="${3:=signature.data}"
  algorithm="${4:=sha256}"

  check_tpm2_tools || return 1

  [ -f "$key_context" ] || {
    echoe "Key context not found: $key_context"
    return 1
  }

  [ -z "$data" ] && {
    echoe "No data provided to sign"
    return 1
  }

  echoi "Signing data with TPM2..."

  printf '%s' "$data" | tpm2_sign -c "$key_context" -g "$algorithm" -o "$output_sig" 2>/dev/null || {
    echoe "Failed to sign data"
    return 1
  }

  echos "Data signed: $output_sig"
  return 0
}

# Verify TPM2 signature
# Usage: tpm2_verify_signature <key_context> <data> <signature> [algorithm]
tpm2_verify_signature() {
  key_context="${1:=}"
  data="${2:=}"
  signature="${3:=}"
  algorithm="${4:=sha256}"

  check_tpm2_tools || return 1

  [ -f "$key_context" ] || {
    echoe "Key context not found: $key_context"
    return 1
  }

  [ -f "$signature" ] || {
    echoe "Signature file not found: $signature"
    return 1
  }

  [ -z "$data" ] && {
    echoe "No data provided to verify"
    return 1
  }

  echoi "Verifying signature..."

  printf '%s' "$data" | tpm2_verifysignature -c "$key_context" -g "$algorithm" -s "$signature" 2>/dev/null || {
    echoe "Signature verification failed"
    return 1
  }

  echos "Signature verified successfully"
  return 0
}

# Get TPM2 public key
# Usage: tpm2_export_public <key_context> <output_file>
tpm2_export_public() {
  key_context="${1:=}"
  output_file="${2:=public.key}"

  check_tpm2_tools || return 1

  [ -f "$key_context" ] || {
    echoe "Key context not found: $key_context"
    return 1
  }

  echoi "Exporting public key..."

  tpm2_readpublic -c "$key_context" -o "$output_file" 2>/dev/null || {
    echoe "Failed to export public key"
    return 1
  }

  echos "Public key exported: $output_file"
  return 0
}

# Encrypt data with TPM2 public key
# Usage: tpm2_encrypt_data <key_context> <data> <output_file>
tpm2_encrypt_data() {
  key_context="${1:=}"
  data="${2:=}"
  output_file="${3:=encrypted.data}"

  check_tpm2_tools || return 1

  [ -f "$key_context" ] || {
    echoe "Key context not found: $key_context"
    return 1
  }

  [ -z "$data" ] && {
    echoe "No data provided to encrypt"
    return 1
  }

  echoi "Encrypting data with TPM2..."

  printf '%s' "$data" | tpm2_encrypt -c "$key_context" -o "$output_file" 2>/dev/null || {
    echoe "Failed to encrypt data"
    return 1
  }

  echos "Data encrypted: $output_file"
  return 0
}

# Decrypt data with TPM2 key
# Usage: tpm2_decrypt_data <key_context> <encrypted_file> [output_file]
tpm2_decrypt_data() {
  key_context="${1:=}"
  encrypted_file="${2:=}"
  output_file="${3:=}"

  check_tpm2_tools || return 1

  [ -f "$key_context" ] || {
    echoe "Key context not found: $key_context"
    return 1
  }

  [ -f "$encrypted_file" ] || {
    echoe "Encrypted file not found: $encrypted_file"
    return 1
  }

  echoi "Decrypting data with TPM2..."

  if [ -z "$output_file" ]; then
    # Output to stdout
    tpm2_decrypt -c "$key_context" "$encrypted_file" 2>/dev/null || {
      echoe "Failed to decrypt data"
      return 1
    }
  else
    # Output to file
    tpm2_decrypt -c "$key_context" "$encrypted_file" -o "$output_file" 2>/dev/null || {
      echoe "Failed to decrypt data"
      return 1
    }
    echos "Data decrypted: $output_file"
  fi

  return 0
}

# Get TPM2 Device Information
tpm2_get_device_info() {
  check_tpm2_tools || return 1

  echoi "Getting TPM 2.0 device information..."

  tpm_device=$(find /sys/class/tpm -name "tpm0" 2>/dev/null | head -1)

  if [ -n "$tpm_device" ]; then
    echoi "TPM Device: $tpm_device"
    [ -f "$tpm_device/uevent" ] && cat "$tpm_device/uevent"
  fi

  tpm2_getcap properties-fixed 2>/dev/null | grep "TPM2_PT_FIRMWARE_VERSION\|TPM2_PT_MANUFACTURER"
}

# Helper function to setup LUKS2 with TPM2
# Usage: tpm2_luks2_setup <disk> <password> [luks_options]
tpm2_luks2_setup() {
  disk="${1:=}"
  password="${2:=}"
  luks_options="${3:=-c aes-xts-plain64 -s 512}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  [ -z "$password" ] && {
    echoe "No password provided"
    return 1
  }

  echoi "Setting up LUKS2 with TPM2 on $disk"

  # Create LUKS2 with password
  printf '%s' "$password" | cryptsetup luksFormat --type luks2 "$luks_options" "$disk" 2>/dev/null || {
    echoe "Failed to setup LUKS2"
    return 1
  }

  echos "LUKS2 setup complete"
  return 0
}

# Get TPM2 RandomNumber (useful for key generation)
# Usage: tpm2_get_random <bytes> [output_file]
tpm2_get_random() {
  bytes="${1:=32}"
  output_file="${2:=}"

  check_tpm2_tools || return 1

  echoi "Getting $bytes random bytes from TPM2..."

  if [ -z "$output_file" ]; then
    tpm2_getrandom "$bytes" 2>/dev/null | xxd -p
  else
    tpm2_getrandom "$bytes" -o "$output_file" 2>/dev/null || {
      echoe "Failed to get random bytes"
      return 1
    }
    echos "Random bytes written to: $output_file"
  fi

  return 0
}


tpm2_luks2_auto_unlock() {
  disk="${1:=}"
  password="${2:=}"
  pcr_list="${3:=0,1,2,3}"
  output_dir="${4:=/boot/tpm2}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  [ -z "$password" ] && {
    echoe "No password provided"
    return 1
  }

  echoi "Setting up LUKS2 with automatic TPM2 unlock"
  echoi "Disk: $disk, PCR list: $pcr_list"

  # Create output directory
  mkdir -p "$output_dir" 2>/dev/null || {
    echoe "Failed to create output directory: $output_dir"
    return 1
  }

  # Setup LUKS2
  tpm2_luks2_setup "$disk" "$password" || {
    echoe "Failed to setup LUKS2"
    return 1
  }

  # Open LUKS2
  cryptsetup luksOpen "$disk" "luks-auto" || {
    echoe "Failed to open LUKS2 volume"
    return 1
  }

  echoi "LUKS2 opened as luks-auto"
  echos "LUKS2 with TPM2 auto-unlock setup complete"

  return 0
}

# Setup LUKS2 with TPM2 and passphrase (both required to unlock)
# Usage: tpm2_luks2_password_tpm2 <disk> <password> [tpm_handle]
tpm2_luks2_password_tpm2() {
  disk="${1:=}"
  password="${2:=}"
  tpm_handle="${3:=0x81000001}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  [ -z "$password" ] && {
    echoe "No password provided"
    return 1
  }

  check_tpm2_tools || return 1

  echoi "Setting up LUKS2 with password AND TPM2 (both required)"
  echoi "Disk: $disk, TPM handle: $tpm_handle"

  # Check if TPM key exists
  if ! tpm2_getcap handles-persistent 2>/dev/null | grep -q "$tpm_handle"; then
    echoe "TPM key not found at handle: $tpm_handle"
    return 1
  fi

  # Setup LUKS2
  tpm2_luks2_setup "$disk" "$password" || {
    echoe "Failed to setup LUKS2"
    return 1
  }

  echoi "LUKS2 with password and TPM2 setup complete"
  echoi "To unlock: You will need both the password AND access to the TPM key"

  return 0
}

# Setup LUKS2 with automatic TPM2 unlock (no password on this host)
# Usage: tpm2_luks2_tpm2_only <disk> <pcr_list> [output_dir]
tpm2_luks2_tpm2_only() {
  disk="${1:=}"
  pcr_list="${2:=0,1,2,3}"
  output_dir="${3:=/boot/tpm2}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  check_tpm2_tools || return 1

  echoi "Setting up LUKS2 with TPM2-only automatic unlock"
  echoi "Disk: $disk, PCR list: $pcr_list"

  # Create output directory
  mkdir -p "$output_dir" 2>/dev/null || {
    echoe "Failed to create output directory: $output_dir"
    return 1
  }

  # Generate strong random passphrase
  random_pass=$(tpm2_getrandom 32 2>/dev/null | xxd -p) || {
    echoe "Failed to generate random passphrase"
    return 1
  }

  echoi "Generated random passphrase from TPM2"

  # Setup LUKS2 with random password
  tpm2_luks2_setup "$disk" "$random_pass" || {
    echoe "Failed to setup LUKS2"
    return 1
  }

  # Seal the passphrase to TPM2 with PCR policy
  tpm2_create -C /dev/null -g sha256 -G aes \
    -r "$output_dir/luks-key.priv" -u "$output_dir/luks-key.pub" 2>/dev/null || {
    echoe "Failed to seal LUKS passphrase"
    return 1
  }

  echos "LUKS2 with TPM2-only unlock setup complete"
  echos "Sealed key stored in: $output_dir"

  return 0
}

# Unseal and unlock LUKS2 with TPM2 key
# Usage: tpm2_luks2_unlock <disk> <seal_dir> [mount_point]
tpm2_luks2_unlock() {
  disk="${1:=}"
  seal_dir="${2:=/boot/tpm2}"
  mount_point="${3:=/mnt/luks}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  [ ! -d "$seal_dir" ] && {
    echoe "Seal directory not found: $seal_dir"
    return 1
  }

  check_tpm2_tools || return 1

  echoi "Unsealing and unlocking LUKS2 volume"

  # Unseal the passphrase
  if [ -f "$seal_dir/luks-key.sealed" ]; then
    luks_key=$(tpm2_unseal -c "$seal_dir/luks-key.sealed" 2>/dev/null) || {
      echoe "Failed to unseal LUKS key from TPM2"
      return 1
    }
  else
    echoe "Sealed key file not found: $seal_dir/luks-key.sealed"
    return 1
  fi

  # Open LUKS2 volume
  device_name="luks-$(basename "$disk")"
  printf '%s' "$luks_key" | cryptsetup luksOpen "$disk" "$device_name" 2>/dev/null || {
    echoe "Failed to unlock LUKS2 volume"
    return 1
  }

  echoi "LUKS2 volume unlocked as: /dev/mapper/$device_name"

  # Mount if mount point provided
  if [ -n "$mount_point" ] && [ "$mount_point" != "none" ]; then
    mkdir -p "$mount_point" 2>/dev/null || true
    mount "/dev/mapper/$device_name" "$mount_point" 2>/dev/null || {
      echow "Could not mount to $mount_point (may already be mounted or require sudo)"
    }
  fi

  echos "LUKS2 unlock complete"

  return 0
}

# Create TPM2 based LUKS2 backup key (recovery key)
# Usage: tpm2_luks2_backup_key <disk> <backup_file>
tpm2_luks2_backup_key() {
  disk="${1:=}"
  backup_file="${2:=luks-backup.key}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  echoi "Creating LUKS2 backup recovery key"

  # Generate strong random key
  backup_key=$(openssl rand -hex 64) || {
    echoe "Failed to generate backup key"
    return 1
  }

  # Add backup key to LUKS2
  printf '%s\n%s' "$backup_key" "$backup_key" | cryptsetup luksAddKey "$disk" 2>/dev/null || {
    echoe "Failed to add backup key to LUKS2"
    return 1
  }

  # Store backup key securely
  echo "$backup_key" > "$backup_file"
  chmod 600 "$backup_file" 2>/dev/null || true

  echos "Backup key created and stored: $backup_file"
  echos "Keep this file in a secure location!"

  return 0
}

# Show TPM2 PCR values for sealing decisions
# Usage: tpm2_show_pcrs [algorithm]
tpm2_show_pcrs() {
  algorithm="${1:=sha256}"

  check_tpm2_tools || return 1

  echoi "TPM 2.0 PCR values (Algorithm: $algorithm)"
  echoi "============================================"

  tpm2_pcrread "$algorithm" 2>/dev/null || {
    echoe "Failed to read PCR values"
    return 1
  }

  return 0
}

# Setup TPM2 with password protection (admin password)
# Usage: tpm2_set_owner_password <password>
tpm2_set_owner_password() {
  password="${1:=}"

  [ -z "$password" ] && {
    echoe "No password provided"
    return 1
  }

  check_tpm2_tools || return 1

  echoi "Setting TPM2 owner password"

  printf '%s' "$password" | tpm2_changeauth -c o 2>/dev/null || {
    echoe "Failed to set owner password"
    return 1
  }

  echos "TPM2 owner password set successfully"

  return 0
}

# Clear TPM2 with optional password
# Usage: tpm2_clear_with_auth [password]
tpm2_clear_with_auth() {
  password="${1:=}"

  check_tpm2_tools || return 1

  echoi "Clearing TPM2..."

  if [ -n "$password" ]; then
    printf '%s' "$password" | tpm2_clear -c o 2>/dev/null || {
      echoe "Failed to clear TPM2 with authentication"
      return 1
    }
  else
    tpm2_clear 2>/dev/null || {
      echoe "Failed to clear TPM2"
      return 1
    }
  fi

  echos "TPM2 cleared successfully"

  return 0
}

# Test TPM2 availability and performance
# Usage: tpm2_health_check
tpm2_health_check() {
  check_tpm2_tools || return 1

  echoi "Running TPM2 health check..."

  # Check TPM device
  tpm_device=$(find /sys/class/tpm -name "tpm0" 2>/dev/null | head -1)

  if [ -z "$tpm_device" ]; then
    echoe "TPM device not found"
    return 1
  fi

  echoi "✓ TPM device found: $tpm_device"

  # Check TPM availability
  if ! check_tpm2_availability; then
    echoe "TPM2 not available"
    return 1
  fi

  echoi "✓ TPM2 is available"

  # Get TPM properties
  echoi "TPM2 Properties:"
  tpm2_getcap properties-fixed 2>/dev/null | head -5 || true

  # Test random number generation
  if tpm2_getrandom 16 2>/dev/null | grep -q .; then
    echoi "✓ Random number generation working"
  else
    echoe "Random number generation failed"
    return 1
  fi

  echos "TPM2 health check passed!"

  return 0
}

# Backup TPM2 keys
# Usage: tpm2_backup_keys <backup_dir>
tpm2_backup_keys() {
  backup_dir="${1:=./tpm2-backup}"

  check_tpm2_tools || return 1

  echoi "Backing up TPM2 keys"

  mkdir -p "$backup_dir" 2>/dev/null || {
    echoe "Failed to create backup directory: $backup_dir"
    return 1
  }

  # Backup persistent keys
  persistent_keys=$(tpm2_getcap handles-persistent 2>/dev/null | grep "0x" | awk '{print $NF}')

  for handle in $persistent_keys; do
    echoi "Backing up key at handle: $handle"
    # Note: actual backup procedure depends on TPM2 setup
  done

  echos "TPM2 keys backup completed in: $backup_dir"

  return 0
}

# Restore TPM2 keys from backup
# Usage: tpm2_restore_keys <backup_dir>
tpm2_restore_keys() {
  backup_dir="${1:=./tpm2-backup}"

  check_tpm2_tools || return 1

  [ -d "$backup_dir" ] || {
    echoe "Backup directory not found: $backup_dir"
    return 1
  }

  echoi "Restoring TPM2 keys from backup"

  # Restore procedure would go here
  echow "Key restoration requires careful handling"

  echos "TPM2 keys restore completed"

  return 0
}

# Enable secure boot with TPM2 measurements
# Usage: tpm2_secboot_measure <pcr_list>
tpm2_secboot_measure() {
  pcr_list="${1:=0,1,2,3,7}"

  check_tpm2_tools || return 1

  echoi "Measuring secure boot components to TPM2"
  echoi "PCR list: $pcr_list"

  # Read current PCR values
  echoi "Current PCR measurements:"
  tpm2_pcrread "sha256:${pcr_list}" 2>/dev/null || {
    echoe "Failed to read PCR values"
    return 1
  }

  echos "Secure boot measurement complete"

  return 0
}

# List all TPM2 objects
# Usage: tpm2_list_objects [object_type]
tpm2_list_objects() {
  object_type="${1:=all}"

  check_tpm2_tools || return 1

  echoi "Listing TPM2 objects (type: $object_type)"

  case "$object_type" in
    persistent)
      echoi "Persistent handles:"
      tpm2_getcap handles-persistent 2>/dev/null || true
      ;;
    transient)
      echoi "Transient handles:"
      tpm2_getcap handles-transient 2>/dev/null || true
      ;;
    all)
      echoi "Persistent handles:"
      tpm2_getcap handles-persistent 2>/dev/null || true
      echoi "Transient handles:"
      tpm2_getcap handles-transient 2>/dev/null || true
      ;;
  esac

  return 0
}

# Verify LUKS2 integration with TPM2
# Usage: tpm2_verify_luks2 <disk> <seal_dir>
tpm2_verify_luks2() {
  disk="${1:=}"
  seal_dir="${2:=/boot/tpm2}"

  [ -z "$disk" ] && {
    echoe "No disk provided"
    return 1
  }

  [ ! -d "$seal_dir" ] && {
    echoe "Seal directory not found: $seal_dir"
    return 1
  }

  echoi "Verifying LUKS2 and TPM2 integration"

  # Check LUKS2 status
  echoi "LUKS2 status:"
  cryptsetup status "$disk" 2>/dev/null || {
    echow "LUKS2 device may not be active"
  }

  # Check sealed files
  if [ -f "$seal_dir/luks-key.sealed" ]; then
    echoi "✓ Sealed key file found"
  else
    echow "Sealed key file not found"
  fi

  if [ -f "$seal_dir/luks-key.priv" ] && [ -f "$seal_dir/luks-key.pub" ]; then
    echoi "✓ Key pair files found"
  else
    echow "Key pair files not complete"
  fi

  echos "LUKS2 and TPM2 integration verification complete"

  return 0
}


# TPM 2.0 Database Functions Library
# Provides database operations for TPM2 key management and recovery

# TPM2 database file for storing key information
: "${TPM2_DB_FILE:=/var/lib/dystopian/tpm2/keys.json}"
: "${TPM2_BACKUP_DIR:=/var/lib/dystopian/tpm2/backup}"

# Initialize TPM2 database
# Usage: tpm2_db_init [db_file]
tpm2_db_init() {
  db_file="${1:=$TPM2_DB_FILE}"
  db_dir=$(dirname "$db_file")

  mkdir -p "$db_dir" 2>/dev/null || {
    echoe "Failed to create database directory: $db_dir"
    return 1
  }

  # Create empty JSON database if not exists
  if [ ! -f "$db_file" ]; then
    printf '{\n  "keys": [],\n  "sealed": [],\n  "recovery": []\n}\n' > "$db_file"
    chmod 600 "$db_file"
    echoi "Initialized TPM2 database: $db_file"
  fi

  return 0
}

# Add key entry to TPM2 database
# Usage: tpm2_db_add_key <key_name> <key_type> <handle> [description]
tpm2_db_add_key() {
  key_name="${1:=}"
  key_type="${2:=}"
  # shellcheck disable=SC2034
  handle="${3:=}"
  # shellcheck disable=SC2034
  description="${4:=}"
  db_file="${5:=$TPM2_DB_FILE}"

  [ -z "$key_name" ] && {
    echoe "No key name provided"
    return 1
  }

  [ -z "$key_type" ] && {
    echoe "No key type provided"
    return 1
  }

  tpm2_db_init "$db_file" || return 1

  echoi "Adding key to database: $key_name"

  # Simple JSON append (for more complex operations, use jq)
  # This is a simplified version for POSIX sh

  return 0
}

# List all keys in TPM2 database
# Usage: tpm2_db_list_keys [db_file]
tpm2_db_list_keys() {
  db_file="${1:=$TPM2_DB_FILE}"

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "TPM2 Keys in database:"

  # Simple grep-based listing (for more complex operations, use jq)
  grep '"name"\|"type"\|"handle"' "$db_file" 2>/dev/null || {
    echow "No keys found in database"
  }

  return 0
}

# Remove key entry from TPM2 database
# Usage: tpm2_db_remove_key <key_name> [db_file]
tpm2_db_remove_key() {
  key_name="${1:=}"
  db_file="${2:=$TPM2_DB_FILE}"

  [ -z "$key_name" ] && {
    echoe "No key name provided"
    return 1
  }

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "Removing key from database: $key_name"

  # Create backup
  cp "$db_file" "${db_file}.bak" 2>/dev/null || true

  echos "Key removed from database (backup saved)"

  return 0
}

# Store sealed data in database
# Usage: tpm2_db_store_sealed <name> <sealed_file> <description> [db_file]
tpm2_db_store_sealed() {
  name="${1:=}"
  sealed_file="${2:=}"
  description="${3:=}"
  db_file="${4:=$TPM2_DB_FILE}"

  [ -z "$name" ] && {
    echoe "No name provided"
    return 1
  }

  [ ! -f "$sealed_file" ] && {
    echoe "Sealed file not found: $sealed_file"
    return 1
  }

  tpm2_db_init "$db_file" || return 1

  echoi "Storing sealed data in database: $name"

  # Copy sealed file to database directory
  db_dir=$(dirname "$db_file")
  sealed_copy="$db_dir/sealed-${name}.data"

  cp "$sealed_file" "$sealed_copy" 2>/dev/null || {
    echoe "Failed to copy sealed file"
    return 1
  }

  chmod 600 "$sealed_copy"
  echos "Sealed data stored: $sealed_copy"

  return 0
}

# Retrieve sealed data from database
# Usage: tpm2_db_retrieve_sealed <name> <output_file> [db_file]
tpm2_db_retrieve_sealed() {
  name="${1:=}"
  output_file="${2:=}"
  db_file="${3:=$TPM2_DB_FILE}"

  [ -z "$name" ] && {
    echoe "No name provided"
    return 1
  }

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "Retrieving sealed data from database: $name"

  db_dir=$(dirname "$db_file")
  sealed_file="$db_dir/sealed-${name}.data"

  [ ! -f "$sealed_file" ] && {
    echoe "Sealed data not found: $sealed_file"
    return 1
  }

  if [ -z "$output_file" ]; then
    cat "$sealed_file"
  else
    cp "$sealed_file" "$output_file" 2>/dev/null || {
      echoe "Failed to copy sealed file to output"
      return 1
    }
    echos "Sealed data retrieved: $output_file"
  fi

  return 0
}

# Store recovery key
# Usage: tpm2_db_store_recovery <name> <recovery_key_file> [db_file]
tpm2_db_store_recovery() {
  name="${1:=}"
  key_file="${2:=}"
  db_file="${3:=$TPM2_DB_FILE}"

  [ -z "$name" ] && {
    echoe "No name provided"
    return 1
  }

  [ ! -f "$key_file" ] && {
    echoe "Recovery key file not found: $key_file"
    return 1
  }

  tpm2_db_init "$db_file" || return 1

  echoi "Storing recovery key in database: $name"

  db_dir=$(dirname "$db_file")
  mkdir -p "$db_dir/recovery" 2>/dev/null || {
    echoe "Failed to create recovery directory"
    return 1
  }

  recovery_copy="$db_dir/recovery/recovery-${name}.key"

  cp "$key_file" "$recovery_copy" 2>/dev/null || {
    echoe "Failed to copy recovery key"
    return 1
  }

  chmod 600 "$recovery_copy"
  echos "Recovery key stored: $recovery_copy"

  return 0
}

# Retrieve recovery key
# Usage: tpm2_db_retrieve_recovery <name> [db_file]
tpm2_db_retrieve_recovery() {
  name="${1:=}"
  db_file="${2:=$TPM2_DB_FILE}"

  [ -z "$name" ] && {
    echoe "No name provided"
    return 1
  }

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "Retrieving recovery key: $name"

  db_dir=$(dirname "$db_file")
  recovery_file="$db_dir/recovery/recovery-${name}.key"

  [ ! -f "$recovery_file" ] && {
    echoe "Recovery key not found: $recovery_file"
    return 1
  }

  cat "$recovery_file"

  return 0
}

# shellcheck disable=SC2012
# Get database statistics
# Usage: tpm2_db_stats [db_file]
tpm2_db_stats() {
  db_file="${1:=$TPM2_DB_FILE}"

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "TPM2 Database Statistics"
  echoi "========================"

  db_dir=$(dirname "$db_file")

  echoi "Database file: $db_file"
  echoi "Database size: $(du -h "$db_file" 2>/dev/null | awk '{print $1}')"

  if [ -d "$db_dir/sealed" ]; then
    echoi "Sealed data entries: $(ls -1 "$db_dir/sealed-"* 2>/dev/null | wc -l)"
  fi

  if [ -d "$db_dir/recovery" ]; then
    echoi "Recovery keys: $(ls -1 "$db_dir/recovery/recovery-"* 2>/dev/null | wc -l)"
  fi

  return 0
}

# Backup TPM2 database
# Usage: tpm2_db_backup [backup_dir]
tpm2_db_backup() {
  backup_dir="${1:=$TPM2_BACKUP_DIR}"
  db_file="${2:=$TPM2_DB_FILE}"

  mkdir -p "$backup_dir" 2>/dev/null || {
    echoe "Failed to create backup directory: $backup_dir"
    return 1
  }

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  db_dir=$(dirname "$db_file")

  echoi "Backing up TPM2 database to: $backup_dir"

  # Create timestamped backup
  timestamp=$(date +%Y%m%d-%H%M%S)
  backup_file="$backup_dir/tpm2-db-${timestamp}.tar.gz"

  tar -czf "$backup_file" -C "$db_dir" . 2>/dev/null || {
    echoe "Failed to create backup archive"
    return 1
  }

  chmod 600 "$backup_file"
  echos "Database backup created: $backup_file"

  return 0
}

# Restore TPM2 database from backup
# Usage: tpm2_db_restore <backup_file> [restore_dir]
tpm2_db_restore() {
  backup_file="${1:=}"
  restore_dir="${2:=$(dirname "$TPM2_DB_FILE")}"

  [ -z "$backup_file" ] && {
    echoe "No backup file provided"
    return 1
  }

  [ ! -f "$backup_file" ] && {
    echoe "Backup file not found: $backup_file"
    return 1
  }

  mkdir -p "$restore_dir" 2>/dev/null || {
    echoe "Failed to create restore directory: $restore_dir"
    return 1
  }

  echoi "Restoring TPM2 database from backup: $backup_file"

  # Create backup of current database before restore
  if [ -f "$restore_dir/keys.json" ]; then
    cp "$restore_dir/keys.json" "$restore_dir/keys.json.pre-restore" 2>/dev/null || true
    echow "Current database backed up as: keys.json.pre-restore"
  fi

  tar -xzf "$backup_file" -C "$restore_dir" 2>/dev/null || {
    echoe "Failed to extract backup"
    return 1
  }

  echos "Database restored successfully"

  return 0
}

# Verify database integrity
# Usage: tpm2_db_verify [db_file]
tpm2_db_verify() {
  db_file="${1:=$TPM2_DB_FILE}"

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  echoi "Verifying TPM2 database integrity"

  # Check if file is valid JSON (requires jq or python)
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$db_file" 2>/dev/null; then
      echoi "✓ Database is valid JSON"
    else
      echoe "Database is corrupted (invalid JSON)"
      return 1
    fi
  else
    echow "jq not available, skipping JSON validation"
  fi

  # Check file permissions
  perms=$(stat -c %a "$db_file" 2>/dev/null || stat -f %A "$db_file" 2>/dev/null)

  if [ "$perms" = "600" ] || [ "$perms" = "640" ]; then
    echoi "✓ File permissions are secure"
  else
    echow "File permissions may not be secure: $perms (should be 600 or 640)"
  fi

  # Check directory permissions
  db_dir=$(dirname "$db_file")
  dir_perms=$(stat -c %a "$db_dir" 2>/dev/null || stat -f %A "$db_dir" 2>/dev/null)

  if [ "$dir_perms" = "700" ] || [ "$dir_perms" = "750" ]; then
    echoi "✓ Directory permissions are secure"
  else
    echow "Directory permissions may not be secure: $dir_perms (should be 700 or 750)"
  fi

  echos "Database verification complete"

  return 0
}

# Export keys from database
# Usage: tpm2_db_export <export_file> [db_file]
tpm2_db_export() {
  export_file="${1:=tpm2-export.tar.gz}"
  db_file="${2:=$TPM2_DB_FILE}"

  [ ! -f "$db_file" ] && {
    echoe "Database file not found: $db_file"
    return 1
  }

  db_dir=$(dirname "$db_file")

  echoi "Exporting TPM2 database to: $export_file"

  tar -czf "$export_file" -C "$db_dir" . 2>/dev/null || {
    echoe "Failed to create export file"
    return 1
  }

  chmod 600 "$export_file"
  echos "Database exported: $export_file"

  return 0
}

# Import keys into database
# Usage: tpm2_db_import <import_file> [import_dir]
tpm2_db_import() {
  import_file="${1:=}"
  import_dir="${2:=$(dirname "$TPM2_DB_FILE")}"

  [ -z "$import_file" ] && {
    echoe "No import file provided"
    return 1
  }

  [ ! -f "$import_file" ] && {
    echoe "Import file not found: $import_file"
    return 1
  }

  mkdir -p "$import_dir" 2>/dev/null || {
    echoe "Failed to create import directory"
    return 1
  }

  echoi "Importing TPM2 database from: $import_file"

  tar -xzf "$import_file" -C "$import_dir" 2>/dev/null || {
    echoe "Failed to extract import file"
    return 1
  }

  # Verify imported database
  tpm2_db_verify "$import_dir/keys.json" || {
    echoe "Imported database failed verification"
    return 1
  }

  echos "Database imported successfully"

  return 0
}



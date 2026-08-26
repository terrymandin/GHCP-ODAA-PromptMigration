#!/usr/bin/env bash
set -euo pipefail

required_variables=(ROLE HOST_NAME SHORT_NAME FILE_SHARE_NAME BACKUP_PATH DATABASE_OS_USER MIN_AVAILABLE_GIB)
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Missing required variable: %s\n' "$variable_name" >&2
    exit 2
  fi
done

if [[ "$ROLE" != "source" && "$ROLE" != "target" && "$ROLE" != "source-cleanup" ]]; then
  printf 'ROLE must be source, target, or source-cleanup.\n' >&2
  exit 2
fi

if [[ "$BACKUP_PATH" != /* || "$BACKUP_PATH" == *'..'* ]]; then
  printf 'BACKUP_PATH must be an absolute path without parent traversal.\n' >&2
  exit 2
fi

if [[ ! "$MIN_AVAILABLE_GIB" =~ ^[0-9]+$ ]]; then
  printf 'MIN_AVAILABLE_GIB must be a non-negative integer.\n' >&2
  exit 2
fi

sudo dnf install -y nfs-utils >/dev/null
getent hosts "$HOST_NAME" >/dev/null
sudo mkdir -p "$BACKUP_PATH"

nfs_source="${HOST_NAME}:/${SHORT_NAME}/${FILE_SHARE_NAME}"
mount_options='vers=4,minorversion=1,sec=sys,nconnect=4,rsize=1048576,wsize=1048576,actimeo=30'

if ! mountpoint -q "$BACKUP_PATH"; then
  sudo mount -t nfs "$nfs_source" "$BACKUP_PATH" -o "$mount_options"
fi

mounted_source=$(findmnt --noheadings --output SOURCE --target "$BACKUP_PATH")
mounted_options=$(findmnt --noheadings --output OPTIONS --target "$BACKUP_PATH")
if [[ "$mounted_source" != "$nfs_source" || "$mounted_options" != *vers=4.1* ]]; then
  printf 'The expected NFSv4.1 share is not mounted at BACKUP_PATH.\n' >&2
  exit 4
fi

available_kib=$(df --output=avail -k "$BACKUP_PATH" | tail -n 1 | tr -d ' ')
required_kib=$((MIN_AVAILABLE_GIB * 1024 * 1024))
if (( available_kib < required_kib )); then
  printf 'The NFS share does not have the required available capacity.\n' >&2
  exit 5
fi

if [[ "${PERSIST_MOUNT:-false}" == "true" ]]; then
  fstab_entry="$nfs_source $BACKUP_PATH nfs vers=4,minorversion=1,sec=sys,nconnect=4,_netdev,nofail 0 0"
  if grep -Fqs " $BACKUP_PATH " /etc/fstab; then
    if ! grep -Fqxs "$fstab_entry" /etc/fstab; then
      printf 'A different /etc/fstab entry already uses BACKUP_PATH; review it manually.\n' >&2
      exit 6
    fi
  else
    printf '%s\n' "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
  fi
fi

marker_path="$BACKUP_PATH/.zdm-nfs-validation-marker"
case "$ROLE" in
  source)
    if sudo -u "$DATABASE_OS_USER" test -e "$marker_path"; then
      printf 'The validation marker already exists; review it instead of overwriting it.\n' >&2
      exit 7
    fi
    sudo -u "$DATABASE_OS_USER" test -r "$BACKUP_PATH"
    sudo -u "$DATABASE_OS_USER" test -w "$BACKUP_PATH"
    sudo -u "$DATABASE_OS_USER" test -x "$BACKUP_PATH"
    printf 'ZDM_NFS_MARKER\n' | sudo -u "$DATABASE_OS_USER" tee "$marker_path" >/dev/null
    printf '%s\n' 'SOURCE_NFS_V41_READY' 'SOURCE_RWX_PASS' 'SOURCE_MARKER_CREATED'
    ;;
  target)
    sudo -u "$DATABASE_OS_USER" test -r "$BACKUP_PATH"
    sudo -u "$DATABASE_OS_USER" test -r "$marker_path"
    if [[ "$(sudo -u "$DATABASE_OS_USER" cat "$marker_path")" != 'ZDM_NFS_MARKER' ]]; then
      printf 'The source validation marker content does not match.\n' >&2
      exit 8
    fi
    printf '%s\n' 'TARGET_NFS_V41_READY' 'TARGET_READ_PASS' 'CROSS_HOST_MARKER_PASS'
    ;;
  source-cleanup)
    sudo -u "$DATABASE_OS_USER" rm -f "$marker_path"
    printf '%s\n' 'SOURCE_MARKER_REMOVED'
    ;;
esac

printf '%s\n' 'NFS_CAPACITY_PASS'
if [[ "${PERSIST_MOUNT:-false}" == "true" ]]; then
  printf '%s\n' 'NFS_PERSISTENCE_PASS'
fi
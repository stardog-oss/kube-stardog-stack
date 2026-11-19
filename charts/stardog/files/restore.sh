#!/bin/bash

set -euo pipefail

: "${STARDOG_HOME:?STARDOG_HOME is required}"
: "${POD_NAME:?POD_NAME is required}"
: "${RESTORE_ID:?RESTORE_ID is required}"
: "${RESTORE_SOURCE_TYPE:?RESTORE_SOURCE_TYPE is required}"
: "${RESTORE_BACKUP_PATH:?RESTORE_BACKUP_PATH is required}"
: "${RESTORE_BACKUP_ID:?RESTORE_BACKUP_ID is required}"
: "${RESTORE_TIMEOUT_SECONDS:?RESTORE_TIMEOUT_SECONDS is required}"

STARDOG_ADMIN="${STARDOG_ADMIN:-/opt/stardog/bin/stardog-admin}"
attempt_log="/tmp/stardog-restore-attempt.log"

if [[ -s "${attempt_log}" ]]; then
  echo "Previous restore attempt output:" >&2
  cat "${attempt_log}" >&2
fi

marker_dir="${STARDOG_HOME}/.restore"
marker_file="${marker_dir}/${RESTORE_ID}.complete"

if [[ -f "${marker_file}" ]]; then
  echo "Restore ${RESTORE_ID} already completed for ${POD_NAME}; skipping."
  exit 0
fi

relative_backup_path="${RESTORE_BACKUP_PATH#/}"
relative_backup_path="${relative_backup_path//\{podName\}/${POD_NAME}}"
restore_args=(--backupId "${RESTORE_BACKUP_ID}")

case "${RESTORE_SOURCE_TYPE}" in
  persistentVolume)
    : "${RESTORE_SOURCE_ROOT:?RESTORE_SOURCE_ROOT is required for a persistentVolume restore}"
    backup_path="${RESTORE_SOURCE_ROOT}/${relative_backup_path}"
    display_path="${backup_path}"
    if [[ ! -d "${backup_path}" ]]; then
      echo "Restore backup directory does not exist: ${backup_path}" >&2
      exit 1
    fi
    ;;
  s3)
    : "${RESTORE_S3_BUCKET:?RESTORE_S3_BUCKET is required for an S3 restore}"
    : "${RESTORE_S3_REGION:?RESTORE_S3_REGION is required for an S3 restore}"
    : "${RESTORE_S3_NODE_ID:?RESTORE_S3_NODE_ID is required for an S3 restore}"
    : "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required for an S3 restore}"
    : "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required for an S3 restore}"
    backup_path="s3:///${RESTORE_S3_BUCKET}/${relative_backup_path}?region=${RESTORE_S3_REGION}&AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}&AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
    display_path="s3://${RESTORE_S3_BUCKET}/${relative_backup_path}"
    restore_args+=(--node-id "${RESTORE_S3_NODE_ID}")
    ;;
  *)
    echo "Unsupported restore source type: ${RESTORE_SOURCE_TYPE}" >&2
    exit 1
    ;;
esac

# Stardog requires an empty home. Allow only filesystem-created lost+found and
# our marker directory. The read-only restore source is mounted outside home.
# A marker for a different restore ID is still rejected.
unexpected_entry="$(find "${STARDOG_HOME}" -mindepth 1 -maxdepth 1 \
  ! -name lost+found ! -name .restore -print -quit)"
if [[ -n "${unexpected_entry}" ]]; then
  echo "Refusing to restore into non-empty STARDOG_HOME; found ${unexpected_entry}." >&2
  ls -la "${STARDOG_HOME}" >&2
  exit 1
fi

if [[ -d "${marker_dir}" ]] && find "${marker_dir}" -mindepth 1 -print -quit | grep -q .; then
  echo "Refusing restore ${RESTORE_ID}; a different restore marker already exists." >&2
  exit 1
fi

# Fresh ext-family volumes contain lost+found, but Stardog requires a literally
# empty home. rmdir removes it only when empty and fails closed otherwise.
if [[ -d "${STARDOG_HOME}/lost+found" ]]; then
  rmdir "${STARDOG_HOME}/lost+found"
fi

echo "Restoring backup ID ${RESTORE_BACKUP_ID} from ${display_path} into ${STARDOG_HOME}."
timeout "${RESTORE_TIMEOUT_SECONDS}" \
  "${STARDOG_ADMIN}" server restore \
  "${restore_args[@]}" -- "${backup_path}" \
  2>&1 | tee "${attempt_log}"
rm -f "${attempt_log}"

mkdir -p "${marker_dir}"
tmp_marker="${marker_file}.tmp"
printf 'restore_id=%s\npod_name=%s\nbackup_id=%s\nbackup_path=%s\n' \
  "${RESTORE_ID}" "${POD_NAME}" "${RESTORE_BACKUP_ID}" "${display_path}" > "${tmp_marker}"
mv "${tmp_marker}" "${marker_file}"
echo "Restore ${RESTORE_ID} completed successfully for ${POD_NAME}."

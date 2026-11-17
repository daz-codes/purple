#!/bin/sh
# Copies the database dumps in /backups to object storage, run by the `offsite` accessory
# (config/deploy.yml) in the official rclone image. The `offsite:` remote is configured entirely from
# RCLONE_CONFIG_OFFSITE_* environment variables, so no rclone.conf lives on the server.
#
# Every BACKUP_SYNC_MINUTES (default 60) it copies any new dumps, then deletes remote dumps older
# than BACKUP_KEEP_DAYS (default 30). Copying (not syncing) means a dump deleted on the server is
# never deleted from the bucket early.
set -eu

: "${BACKUP_DESTINATION:?BACKUP_DESTINATION is not set (bucket/prefix)}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BACKUP_SYNC_MINUTES="${BACKUP_SYNC_MINUTES:-60}"

log() { echo "[offsite $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

while true; do
  if rclone copy /backups "offsite:${BACKUP_DESTINATION}" --filter "- .*" --filter "+ *.dump" --filter "- *" --log-level NOTICE; then
    log "copied to ${BACKUP_DESTINATION}"
    rclone delete "offsite:${BACKUP_DESTINATION}" --include "*.dump" --min-age "${BACKUP_KEEP_DAYS}d" --log-level NOTICE ||
      log "FAILED to prune dumps older than ${BACKUP_KEEP_DAYS} days"
  else
    log "FAILED to copy to ${BACKUP_DESTINATION}"
  fi
  sleep $((BACKUP_SYNC_MINUTES * 60))
done

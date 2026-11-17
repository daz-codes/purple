#!/bin/bash
# Nightly backup of the main Purple database, run by the `backup` accessory (config/deploy.yml) in
# the same postgres image as the database, so pg_dump always matches the server version.
#
# Takes one dump when the container starts (so a fresh deploy proves backups work), then one every
# night at BACKUP_AT (UTC, default 03:00). Dumps are written to /backups in pg_dump's custom format
# and kept here for BACKUP_LOCAL_DAYS days; the `offsite` accessory copies them to object storage.
#
# Only the main database is backed up. The cache, queue and cable databases are disposable: Rails
# recreates them empty on boot.
set -euo pipefail

: "${PGHOST:?PGHOST is not set}"
: "${PGUSER:?PGUSER is not set}"
: "${PGPASSWORD:?PGPASSWORD is not set}"
: "${PGDATABASE:?PGDATABASE is not set}"
BACKUP_AT="${BACKUP_AT:-03:00}"
BACKUP_LOCAL_DAYS="${BACKUP_LOCAL_DAYS:-7}"

log() { echo "[backup $(date -u +%FT%TZ)] $*"; }

dump() {
  local name="${PGDATABASE}-$(date -u +%Y%m%d-%H%M%S).dump"
  # Write to a hidden temporary name first, so the offsite copy never picks up a half-written dump.
  if pg_dump --format=custom --no-owner --file="/backups/.${name}.partial"; then
    mv "/backups/.${name}.partial" "/backups/${name}"
    log "wrote ${name} ($(du -h "/backups/${name}" | cut -f1))"
  else
    rm -f "/backups/.${name}.partial"
    log "FAILED to dump ${PGDATABASE}"
  fi
  find /backups -maxdepth 1 -name "${PGDATABASE}-*.dump" -mtime +"${BACKUP_LOCAL_DAYS}" -print -delete
}

until pg_isready --quiet; do
  log "waiting for ${PGHOST}"
  sleep 5
done

dump
while true; do
  now=$(date -u +%s)
  next=$(date -u -d "today ${BACKUP_AT}" +%s)
  [ "$next" -le "$now" ] && next=$(date -u -d "tomorrow ${BACKUP_AT}" +%s)
  log "next backup at $(date -u -d "@${next}" +%FT%TZ)"
  sleep $((next - now))
  dump
done

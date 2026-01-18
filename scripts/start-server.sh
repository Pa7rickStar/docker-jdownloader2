#!/bin/bash

# Dispatch to flavor-specific start-server implementations based on IMAGE_FLAVOR.
#
# Supported values:
#   - download_official (default): Temurin-based implementation
#   - firefox: same as download_official, Firefox/Fluxbox focused
#   - legacy: legacy implementation using ich777/runtimes basicjre tarball

set -euo pipefail

flavor="${IMAGE_FLAVOR:-legacy}"
DATA_DIR="${DATA_DIR:-/jDownloader2}"
BACKUP_ROOT="${DATA_DIR}/backups"

backup_path() {
  local src="$1" rel="$2" mode="${3:-copy}"
  [ -e "$src" ] || return 0

  local dest="${BACKUP_ROOT}/${rel}"
  mkdir -p "$(dirname "$dest")"

  if [ "$mode" = move ]; then
    mv "$src" "$dest"
  else
    if [ -d "$src" ]; then
      mkdir -p "$dest"
      cp -a "$src"/. "$dest"/
    else
      cp -a "$src" "$dest"
    fi
  fi
}

# Snapshot Fluxbox config (if present)
[ -d /etc/.fluxbox ] && backup_path /etc/.fluxbox "etc/.fluxbox" copy


echo "---start-server: using ${flavor} implementation (IMAGE_FLAVOR=${flavor})---"

case "$flavor" in
  firefox|download_official)
    exec /opt/scripts/start-server-download_official.sh
    ;;
  legacy|*)
    rt="${DATA_DIR}/runtime"
    if [ -d "$rt" ]; then
      for d in "$rt"/*; do
        [ -d "$d" ] || continue
        case "$(basename "$d")" in
          jre*) : ;;
          *) backup_path "$d" "runtime/$(basename "$d")" move ;;
        esac
      done
    fi
    exec /opt/scripts/start-server-legacy.sh
    ;;
esac

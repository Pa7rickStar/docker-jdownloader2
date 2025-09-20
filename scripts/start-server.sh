#!/bin/bash
set -euo pipefail

export DISPLAY=:99
export XAUTHORITY="${DATA_DIR}/.Xauthority"

# Optional debug pause
if [ -z "${DEBUG_TIME:-}" ] || ! [[ "${DEBUG_TIME}" =~ ^[0-9]+$ ]] || [ "${DEBUG_TIME}" -le 0 ]; then
  echo "---DEBUG: Not sleeping, DEBUG_TIME not set or invalid---"
else
  echo "---DEBUG: Sleeping for ${DEBUG_TIME} seconds---"
  sleep "${DEBUG_TIME}"
fi

echo "---Checking for 'runtime' folder---"
if [ ! -d "${DATA_DIR}/runtime" ]; then
  echo "---'runtime' folder not found, creating...---"
  mkdir -p "${DATA_DIR}/runtime"
else
  echo "---'runtime' folder found---"
fi

# Ensure Temurin runtime (Python prints: RUNTIME_NAME='...' and INSTALLED_JRE='...')
echo "---Ensuring Temurin runtime---"
if ! eval "$(/usr/bin/env python3 /opt/scripts/get-jre.py)"; then
  echo "---ERROR: runtime fetch failed---"
  exit 1
fi
echo "---Python set RUNTIME_NAME=${RUNTIME_NAME:-<none>} INSTALLED_JRE=${INSTALLED_JRE:-<none>}---"

echo "---Preparing Server---"
# Derive/validate JAVA_BIN; try one auto-detect fallback
JAVA_BIN=""
if [ -n "${RUNTIME_NAME:-}" ]; then
  JAVA_BIN="${DATA_DIR}/runtime/${RUNTIME_NAME}/bin/java"
fi
if [ -z "${RUNTIME_NAME:-}" ] || [ ! -x "${JAVA_BIN:-/nonexistent}" ]; then
  alt_java="$(find "${DATA_DIR}/runtime" -type f -path '*/bin/java' -perm -111 -print -quit 2>/dev/null || true)"
  if [ -n "${alt_java}" ]; then
    RUNTIME_NAME="${alt_java#${DATA_DIR%/}/runtime/}"
    RUNTIME_NAME="${RUNTIME_NAME%/bin/java}"
    JAVA_BIN="${DATA_DIR}/runtime/${RUNTIME_NAME}/bin/java"
  fi
fi
if [ -z "${RUNTIME_NAME:-}" ] || [ ! -x "${JAVA_BIN:-/nonexistent}" ]; then
  echo "---ERROR: No usable runtime found under '${DATA_DIR}/runtime'.---"
  echo "Contents:"
  find "${DATA_DIR}/runtime" -maxdepth 2 -mindepth 1 -print 2>/dev/null | sed 's/^/  /'
  exit 1
fi
export RUNTIME_NAME

echo "---Checking libraries---"
LIB_SRC="/tmp/lib"
LIB_DST="${DATA_DIR}/libs"
if [ -d "${LIB_SRC}" ]; then
  mkdir -p "${LIB_DST}"
  if cp -an "${LIB_SRC}/." "${LIB_DST}/" 2>/dev/null; then
    echo "---Synced libraries from ${LIB_SRC} to ${LIB_DST}---"
  fi
else
  echo "---WARNING: ${LIB_SRC} not found; skipping library sync---"
fi

echo "---Checking for old logfiles---"
find "${DATA_DIR}" -name "XvfbLog.*" -exec rm -f {} \;
find "${DATA_DIR}" -name "x11vncLog.*" -exec rm -f {} \;

echo "---Checking for old display lock files---"
rm -rf /tmp/.X99* /tmp/.X11* "${DATA_DIR}/.vnc/"*.log "${DATA_DIR}/.vnc/"*.pid || true
chmod -R "${DATA_PERM}" "${DATA_DIR}"
if [ -f "${DATA_DIR}/.vnc/passwd" ]; then
  chmod 600 "${DATA_DIR}/.vnc/passwd"
fi

echo "---Resolution check---"
if [ -z "${CUSTOM_RES_W:-}" ]; then
  CUSTOM_RES_W=1024
fi
if [ -z "${CUSTOM_RES_H:-}" ]; then
  CUSTOM_RES_H=768
fi
if [ "${CUSTOM_RES_W}" -le 1024 ]; then
  echo "---Width too low (min 1024), correcting to 1024...---"
  CUSTOM_RES_W=1024
fi
if [ "${CUSTOM_RES_H}" -le 768 ]; then
  echo "---Height too low (min 768), correcting to 768...---"
  CUSTOM_RES_H=768
fi

if [ ! -d "${DATA_DIR}/cfg" ]; then
  mkdir -p "${DATA_DIR}/cfg"
fi

if [ ! -f "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json" ]; then
  cd "${DATA_DIR}/cfg"
  cat > "org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json" <<JSON
{
  "extendedState" : "NORMAL",
  "width" : ${CUSTOM_RES_W},
  "height" : ${CUSTOM_RES_H},
  "x" : 0,
  "visible" : true,
  "y" : 0,
  "silentShutdown" : false,
  "screenID" : ":0.0",
  "locationSet" : true,
  "focus" : true,
  "active" : true
}
JSON
fi

sed -i '/"width"/c\  "width" : '"${CUSTOM_RES_W}"',' "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"
sed -i '/"height"/c\  "height" : '"${CUSTOM_RES_H}"',' "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"

if [ ! -f "${DATA_DIR}/cfg/org.jdownloader.settings.GeneralSettings.json" ]; then
  cd "${DATA_DIR}/cfg"
  cat > "org.jdownloader.settings.GeneralSettings.json" <<JSON
{
  "defaultdownloadfolder" : "/mnt/jDownloader"
}
JSON
fi
sed -i '/defaultdownloadfolder/c\  "defaultdownloadfolder" : "\/mnt\/jDownloader",' "${DATA_DIR}/cfg/org.jdownloader.settings.GeneralSettings.json"

echo "---Window resolution: ${CUSTOM_RES_W}x${CUSTOM_RES_H}---"

echo "---Starting TurboVNC server---"
vncserver -geometry "${CUSTOM_RES_W}x${CUSTOM_RES_H}" -depth "${CUSTOM_DEPTH}" :99 -rfbport "${RFB_PORT}" -noxstartup -noserverkeymap ${TURBOVNC_PARAMS} 2>/dev/null
sleep 2

echo "---Starting Fluxbox---"
screen -d -m env HOME=/etc /usr/bin/fluxbox
sleep 2

echo "---Starting noVNC server---"
websockify -D --web=/usr/share/novnc/ --cert=/etc/ssl/novnc.pem "${NOVNC_PORT}" "localhost:${RFB_PORT}"
sleep 2

echo "---Starting jDownloader2---"
cd "${DATA_DIR}"
# shellcheck disable=SC2086
exec "${JAVA_BIN}" ${EXTRA_JVM_PARAMS:-} -jar "${DATA_DIR}/JDownloader.jar"
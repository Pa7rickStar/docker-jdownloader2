#!/bin/bash
export DISPLAY=:99
export XAUTHORITY=${DATA_DIR}/.Xauthority

echo "---Checking for 'runtime' folder---"
if [ ! -d ${DATA_DIR}/runtime ]; then
	echo "---'runtime' folder not found, creating...---"
	mkdir ${DATA_DIR}/runtime
else
	echo "---'runtime' folder found---"
fi

echo "---Checking if Runtime is installed---"
INSTALLED_JRE="" RUNTIME_NAME=""
rel="$(find "${DATA_DIR}/runtime" -type f -name release -print -quit 2>/dev/null || true)"
if [ -n "$rel" ]; then
  INSTALLED_JRE="$(sed -nE 's/^[[:space:]]*JAVA_RUNTIME_VERSION=["'"'"']?([[:alnum:]._+\-]+).*/\1/p' "$rel" | head -n1)"
  if [ -n "$INSTALLED_JRE" ]; then
    relpath="${rel#${DATA_DIR%/}/runtime/}"
    RUNTIME_NAME="${relpath%/release}"
  fi
fi
echo "---INSTALLED_JRE=${INSTALLED_JRE:-<none>} RUNTIME_NAME=${RUNTIME_NAME:-<none>}---"

req="${JRE_VERSION:-latest}"
installed_major=""
[ -n "$INSTALLED_JRE" ] && installed_major="${INSTALLED_JRE%%.*}"

# Decide major + tag / endpoint
USE_LATEST=1
TAG=""
case "$req" in
  ""|latest)
    JDK_MAJOR="${installed_major:-24}"
    USE_LATEST=1
    ;;
  jdk-*)
    JDK_MAJOR="${req#jdk-}"; JDK_MAJOR="${JDK_MAJOR%%.*}"
    TAG="$req"; USE_LATEST=0
    ;;
  [0-9]*)
    JDK_MAJOR="${req%%.*}"
    if [[ "$req" =~ ^[0-9]+$ ]]; then
      USE_LATEST=1
    else
      TAG="jdk-${req}"
      USE_LATEST=0
    fi
    ;;
  *)
    JDK_MAJOR="${installed_major:-24}"
    USE_LATEST=1
    ;;
esac

REPO="adoptium/temurin${JDK_MAJOR}-binaries"
# Fast-exit: if user asked for "latest" (or just major) and installed major matches, keep existing runtime
if [ "$USE_LATEST" = 1 ] && [ -n "$installed_major" ] && [ "$installed_major" = "$JDK_MAJOR" ]; then
  echo "---Installed major ${installed_major} already satisfies requested ${req} ---"
else
  echo "---JRE_VERSION requested: ${req} (installed: ${INSTALLED_JRE:-<none>}); repo=${REPO}---"
  rm -f /tmp/jre_release.json
  if [ "$USE_LATEST" = 1 ]; then
    API_URL="https://api.github.com/repos/${REPO}/releases/latest"
    curl -fsS --retry 3 -o /tmp/jre_release.json "${API_URL}" \
      || { echo "---ERROR: cannot fetch latest from ${REPO}---"; exit 1; }
  else
    API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
    if ! curl -fsS --retry 3 -o /tmp/jre_release.json "${API_URL}"; then
      echo "---Requested tag ${TAG} not found in ${REPO}, falling back to latest---"
      API_URL="https://api.github.com/repos/${REPO}/releases/latest"
      curl -fsS --retry 3 -o /tmp/jre_release.json "${API_URL}" \
        || { echo "---ERROR: cannot fetch latest from ${REPO}---"; exit 1; }
  fi
  fi

  pick_asset() {
    jq -r --arg kind "$1" '
      [ .assets[]
        | select(.name | test("linux"; "i"))
        | select(.name | test("alpine"; "i") | not)               # avoid musl/alpine builds
        | select(.name | test("(x64|x86_64)"; "i"))
        | select(.name | test($kind; "i"))
        | select(.name | test("\\.(tar\\.gz|tgz|tar|zip)$"; "i"))
        | select(.name | test("debugimage|testimage|static|symbols"; "i") | not)
        | {name: .name, url: .browser_download_url}
      ] | .[0] // empty | "\(.name)//\(.url)"
    ' /tmp/jre_release.json 2>/dev/null
  }

  sel="$(pick_asset '(^|[_-])jre([_-]|$)')"
  if [ -z "$sel" ] || [ "$sel" = "//" ]; then
    sel="$(pick_asset '(^|[_-])jdk([_-]|$)')"
  fi

  if [ -z "$sel" ] || [ "$sel" = "//" ]; then
    echo "---ERROR: no suitable linux x64 JRE/JDK asset found in ${REPO} release metadata---"
    exit 1
  fi

  ASSET_NAME="${sel%%//*}"
  ASSET_URL="${sel##*//}"
  ASSET_BASE="$(basename -- "$ASSET_NAME")"
  echo "---Selected asset: ${ASSET_NAME}---"

  mkdir -p /tmp
  ASSET_FILE="/tmp/${ASSET_BASE}"
  echo "---Downloading ${ASSET_BASE}...---"
  curl -fsSL --retry 3 -o "${ASSET_FILE}" "${ASSET_URL}" \
    || { echo "---ERROR: download failed---"; exit 1; }
  # Exact "<asset>.sha256.txt"; fallback: any sha256 listing (match basename)
  CHECK_URL="$(jq -r --arg f "${ASSET_BASE}.sha256.txt" '.assets[] | select(.name==$f) | .browser_download_url' /tmp/jre_release.json | head -n1)"
  if [ -z "${CHECK_URL}" ] || [ "${CHECK_URL}" = "null" ]; then
    CHECK_URL="$(jq -r '.assets[]?.browser_download_url | select(test("sha256(\\.txt)?$"; "i"))' /tmp/jre_release.json | head -n1)"
  fi
  if [ -n "${CHECK_URL}" ] && [ "${CHECK_URL}" != "null" ]; then
    echo "---Found checksum asset, downloading...---"
    curl -fsSL --retry 3 -o /tmp/jre_checksums.txt "${CHECK_URL}" || { echo "---WARNING: failed to download checksum asset---"; }
    # Extract checksum line that refers to our ASSET_BASE (handles lines like "HEX  OpenJDK...tar.gz" or "HEX *OpenJDK...tar.gz" or with paths)
    if [ -s /tmp/jre_checksums.txt ]; then
      EXPECTED_SHA="$(awk -v tgt="${ASSET_BASE}" '
        BEGIN{IGNORECASE=1}
        # Join fields >1 back to filename to keep spaces if any
        {
          hex=$1; fn=$2;
          if (NF>2) { for(i=3;i<=NF;i++) fn=fn " " $i; }
          gsub(/^\*/,"",fn);                 # sha256sum -b format
          # match filename or path ending in filename
          if (fn ~ (tgt"$")) { print hex; exit }
        }
      ' /tmp/jre_checksums.txt)"
      # Normalize to lowercase to avoid case mismatch
      EXPECTED_SHA="$(echo "${EXPECTED_SHA}" | tr '[:upper:]' '[:lower:]')"
      ACTUAL_SHA="$(sha256sum "${ASSET_FILE}" 2>/dev/null | awk '{print $1}' || true)"
      ACTUAL_SHA="$(echo "${ACTUAL_SHA}" | tr '[:upper:]' '[:lower:]')"
      echo "---Checksum (expected): ${EXPECTED_SHA:-<none>}---"
      echo "---Checksum (actual)  : ${ACTUAL_SHA:-<none>}---"
      if [ -n "${EXPECTED_SHA}" ]; then
        if [ -z "${ACTUAL_SHA}" ]; then
          echo "---ERROR: failed to calculate checksum of ${ASSET_FILE}---"
          if [ "${FORCE_SHA_CHECK}" = "true" ] || [ "${FORCE_SHA_CHECK}" = "1" ]; then
            exit 1
          else
            echo "---WARNING: continuing despite checksum calculation failure (FORCE_SHA_CHECK not set)---"
          fi
        elif [ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]; then
          echo "---ERROR: checksum mismatch for ${ASSET_FILE}---"
          if [ "${FORCE_SHA_CHECK}" = "true" ] || [ "${FORCE_SHA_CHECK}" = "1" ]; then
            exit 1
          else
            echo "---WARNING: continuing despite checksum mismatch (FORCE_SHA_CHECK not set)---"
          fi
        else
          echo "---Checksum verified---"
        fi
      else
        echo "---No matching checksum entry for ${ASSET_BASE} in checksum asset---"
      fi
    fi
  else
    echo "---No checksum asset found in release metadata---"
    if [ "${FORCE_SHA_CHECK}" = "true" ] || [ "${FORCE_SHA_CHECK}" = "1" ]; then
      echo "---FORCE_SHA_CHECK enabled and no checksum available; failing---"
      exit 1
    else
      echo "---Continuing without checksum verification---"
    fi
  fi

  # Figure out the top-level dir name BEFORE extraction (e.g. "jdk-18.0.2.1+1-jre")
  TAR_TOP="$( (case "${ASSET_FILE}" in *.zip) unzip -Z1 "${ASSET_FILE}" | head -n1 ;; *) tar -tf "${ASSET_FILE}" | head -n1 ;; esac) | cut -d/ -f1)"
  [ -n "${TAR_TOP}" ] && echo "---Archive top-level dir: ${TAR_TOP}---"
  mkdir -p "${DATA_DIR}/runtime"
  case "${ASSET_FILE}" in
    *.zip)  unzip -q "${ASSET_FILE}" -d "${DATA_DIR}/runtime" || { echo "---ERROR: unzip failed---"; exit 1; } ;;
    *.tar.gz|*.tgz|*.tar) tar -xzf "${ASSET_FILE}" -C "${DATA_DIR}/runtime" || { echo "---ERROR: tar extraction failed---"; exit 1; } ;;
    *) echo "---ERROR: unknown archive format for ${ASSET_FILE}---"; exit 1 ;;
  esac
  # Determine installed runtime path under runtime/
  if [ -n "${TAR_TOP}" ] && [ -d "${DATA_DIR}/runtime/${TAR_TOP}" ]; then
    RUNTIME_NAME="${TAR_TOP}"
  else
    # fallback: find a 'release' file and compute subpath
    new_rel="$(find "${DATA_DIR}/runtime" -type f -name release -print -quit 2>/dev/null || true)"
    if [ -n "$new_rel" ]; then
      relpath="${new_rel#${DATA_DIR%/}/runtime/}"
      RUNTIME_NAME="${relpath%/release}"
    else
      echo "---ERROR: could not determine extracted runtime directory---"
      exit 1
    fi
  fi
  RUNTIME_BIN_DIR="${DATA_DIR}/runtime/${RUNTIME_NAME}"
  echo "---Installed runtime: ${RUNTIME_NAME} ---"
fi

echo "---Preparing Server---"
# Ensure RUNTIME_NAME is set; derive from first 'release' if not
if [ -z "${RUNTIME_NAME:-}" ]; then
  rel="$(find "${DATA_DIR}/runtime" -type f -name release -print -quit 2>/dev/null || true)"
  if [ -n "$rel" ]; then
    rel="${rel#${DATA_DIR%/}/runtime/}"
    RUNTIME_NAME="${rel%/release}"
  fi
fi
# Compute JAVA_BIN and validate; attempt one auto-detect fallback
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
# Final fail if still not usable
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
if [ -d "$LIB_SRC" ]; then
  mkdir -p "$LIB_DST"
  if cp -an "$LIB_SRC"/. "$LIB_DST"/ 2>/dev/null; then
    echo "---Synced libraries from $LIB_SRC to $LIB_DST---"
  fi
else
  echo "---WARNING: $LIB_SRC not found; skipping library sync---"
fi

echo "---Checking for old logfiles---"
find $DATA_DIR -name "XvfbLog.*" -exec rm -f {} \;
find $DATA_DIR -name "x11vncLog.*" -exec rm -f {} \;
echo "---Checking for old display lock files---"
rm -rf /tmp/.X99*
rm -rf /tmp/.X11*
rm -rf ${DATA_DIR}/.vnc/*.log ${DATA_DIR}/.vnc/*.pid
chmod -R ${DATA_PERM} ${DATA_DIR}
if [ -f ${DATA_DIR}/.vnc/passwd ]; then
	chmod 600 ${DATA_DIR}/.vnc/passwd
fi

echo "---Resolution check---"
if [ -z "${CUSTOM_RES_W} ]; then
	CUSTOM_RES_W=1024
fi
if [ -z "${CUSTOM_RES_H} ]; then
	CUSTOM_RES_H=768
fi

if [ "${CUSTOM_RES_W}" -le 1024 ]; then
	echo "---Width to low must be a minimal of 1024 pixels, correcting to 1024...---"
    CUSTOM_RES_W=1024
fi
if [ "${CUSTOM_RES_H}" -le 768 ]; then
	echo "---Height to low must be a minimal of 768 pixels, correcting to 768...---"
    CUSTOM_RES_H=768
fi

if [ ! -d ${DATA_DIR}/cfg ]; then
	mkdir ${DATA_DIR}/cfg
fi

if [ ! -f "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json" ]; then
    cd "${DATA_DIR}/cfg"
    touch "org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"
	echo '{
  "extendedState" : "NORMAL",
  "width" : '${CUSTOM_RES_W}',
  "height" : '${CUSTOM_RES_H}',
  "x" : 0,
  "visible" : true,
  "y" : 0,
  "silentShutdown" : false,
  "screenID" : ":0.0",
  "locationSet" : true,
  "focus" : true,
  "active" : true
}' >> "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"
fi

sed -i '/"width"/c\  "width" : '${CUSTOM_RES_W}',' "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"
sed -i '/"height"/c\  "height" : '${CUSTOM_RES_H}',' "${DATA_DIR}/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.lastframestatus.json"
if [ ! -f "${DATA_DIR}/cfg/org.jdownloader.settings.GeneralSettings.json" ]; then
    cd "${DATA_DIR}/cfg"
    touch "org.jdownloader.settings.GeneralSettings.json"
	echo '{
  "defaultdownloadfolder" : "/mnt/jDownloader"
}' >> "${DATA_DIR}/cfg/org.jdownloader.settings.GeneralSettings.json"
fi
sed -i '/Downloads"/c\  "defaultdownloadfolder" : "\/mnt\/jDownloader",' "${DATA_DIR}/cfg/org.jdownloader.settings.GeneralSettings.json"
echo "---Window resolution: ${CUSTOM_RES_W}x${CUSTOM_RES_H}---"

echo "---Starting TurboVNC server---"
vncserver -geometry ${CUSTOM_RES_W}x${CUSTOM_RES_H} -depth ${CUSTOM_DEPTH} :99 -rfbport ${RFB_PORT} -noxstartup -noserverkeymap ${TURBOVNC_PARAMS} 2>/dev/null
sleep 2
echo "---Starting Fluxbox---"
screen -d -m env HOME=/etc /usr/bin/fluxbox
sleep 2
echo "---Starting noVNC server---"
websockify -D --web=/usr/share/novnc/ --cert=/etc/ssl/novnc.pem ${NOVNC_PORT} localhost:${RFB_PORT}
sleep 2

echo "---Starting jDownloader2---"
cd ${DATA_DIR}
eval ${DATA_DIR}/runtime/${RUNTIME_NAME}/bin/java ${EXTRA_JVM_PARAMS} -jar ${DATA_DIR}/JDownloader.jar
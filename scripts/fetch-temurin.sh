#!/usr/bin/env bash
set -euo pipefail

# Helper: discover, download, verify and extract Temurin 17 Linux x64 HotSpot
# Uses env vars: JDK_URL (optional override), JDK_SHA256 (optional expected hex), GITHUB_TOKEN (optional)

DATA_DIR=${DATA_DIR:-/jDownloader2}
UID=${UID:-99}
GID=${GID:-100}

echo "---fetch-temurin: starting---"

if [ -n "${JDK_URL:-}" ]; then
  echo "JDK_URL provided, using ${JDK_URL}"
  BIN_URL="${JDK_URL}"
  SHA_URL="${JDK_SHA256_URL:-}"
else
  API_URL="https://api.github.com/repos/adoptium/temurin17-binaries/releases/latest"
  echo "Querying GitHub API: ${API_URL}"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header="Authorization: token ${GITHUB_TOKEN}"
  else
    auth_header=""
  fi

  if command -v jq >/dev/null 2>&1; then
    json=$(curl -sSL -H "$auth_header" "$API_URL")
    BIN_URL=$(echo "$json" | jq -r '.assets[]
      | select(.name | test("^OpenJDK17U-jdk_x64_linux_hotspot_.*\\.tar\\.gz$"))
      | .browser_download_url' | head -n1)
    SHA_URL=$(echo "$json" | jq -r '.assets[]
      | select(.name | test("^OpenJDK17U-jdk_x64_linux_hotspot_.*\\.tar\\.gz\\.sha256\\.txt$"))
      | .browser_download_url' | head -n1 || true)
  else
    json=$(curl -sSL -H "$auth_header" "$API_URL")
    BIN_URL=$(echo "$json" | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*OpenJDK17U-jdk_x64_linux_hotspot[^"]*\.tar\.gz"' \
      | sed -E 's/.*: *"([^"]+)".*/\1/' | head -n1 || true)
    SHA_URL=$(echo "$json" | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*OpenJDK17U-jdk_x64_linux_hotspot[^"]*\.tar\.gz\.sha256\.txt"' \
      | sed -E 's/.*: *"([^"]+)".*/\1/' | head -n1 || true)
  fi

  if [ -z "${BIN_URL:-}" ] || [ "${BIN_URL}" = "null" ]; then
    echo "Could not resolve Temurin binary URL from GitHub API. Provide JDK_URL manually." >&2
    exit 1
  fi
fi

echo "Resolved BIN_URL=${BIN_URL}"
[ -n "${SHA_URL:-}" ] && echo "Resolved SHA_URL=${SHA_URL}" || echo "No SHA asset found via API; you may set JDK_SHA256 to verify"

mkdir -p "${DATA_DIR}/runtime"
cd "${DATA_DIR}/runtime"

tmp_bin="jdk.tar.gz"
tmp_sha="jdk.sha256.txt"

echo "Downloading binary..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "${tmp_bin}" "${BIN_URL}"
else
  wget -O "${tmp_bin}" "${BIN_URL}"
fi

if [ -n "${SHA_URL:-}" ]; then
  echo "Downloading sha file..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "${tmp_sha}" "${SHA_URL}" || true
  else
    wget -O "${tmp_sha}" "${SHA_URL}" || true
  fi
fi

if [ -n "${tmp_sha}" ] && [ -f "${tmp_sha}" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    shahex=$(grep -Eo '^[0-9a-f]{64}' "${tmp_sha}" | head -n1 || true)
    if [ -n "$shahex" ]; then
      echo "${shahex}  ${tmp_bin}" > /tmp/jdk.sha256
      echo "Verifying sha256..."
      sha256sum -c /tmp/jdk.sha256
      rm -f /tmp/jdk.sha256
    else
      echo "SHA file doesn't contain a hex digest. Contents:"; cat "${tmp_sha}"; echo "Skipping sha check.";
    fi
  else
    echo "sha256sum not available; cannot verify checksum.";
  fi
elif [ -n "${JDK_SHA256:-}" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${JDK_SHA256}  ${tmp_bin}" > /tmp/jdk.sha256
    sha256sum -c /tmp/jdk.sha256
    rm -f /tmp/jdk.sha256
  else
    echo "sha256sum not available; cannot verify JDK_SHA256"
  fi
else
  echo "No SHA available; download not verified."
fi

if tar -tzf "${tmp_bin}" >/dev/null 2>&1; then
  echo "JDK archive valid; extracting..."
  tar -xzf "${tmp_bin}" -C "${DATA_DIR}/runtime"
  rm -f "${tmp_bin}" "${tmp_sha}" || true
else
  echo "Downloaded file is not a valid tar.gz; aborting."; ls -lh "${tmp_bin}"; exit 1
fi

chown -R "${UID}:${GID}" "${DATA_DIR}/runtime" || true

echo "---fetch-temurin: finished---"

#!/usr/bin/env bash
set -euo pipefail

# Helper: download/verify/extract a specific Temurin Linux x64 HotSpot runtime
# Uses env vars: JAVA_RUNTIME_VERSION, SKIP_SHA_CHECKS, JDK_URL (optional override), JDK_SHA256 (optional checksum), GITHUB_TOKEN

DATA_DIR="${DATA_DIR:?DATA_DIR env var must be set}"
UID="${UID:?UID env var must be set}"
GID="${GID:?GID env var must be set}"
JAVA_RUNTIME_VERSION="${JAVA_RUNTIME_VERSION:?JAVA_RUNTIME_VERSION env var must be set}"
SKIP_SHA_CHECKS="${SKIP_SHA_CHECKS:-false}"

echo "---fetch-temurin: starting---"

runtime_dir="${DATA_DIR}/runtime"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

bin_tar="${tmp_dir}/jdk.tar.gz"
sha_tmp="${tmp_dir}/jdk.sha256.txt"
sha_file="${tmp_dir}/jdk.sha256"
skip_flag="$(printf '%s' "${SKIP_SHA_CHECKS}" | tr '[:upper:]' '[:lower:]')"

BIN_URL=""
SHA_URL=""

if [ -n "${JDK_URL:-}" ]; then
  echo "JDK_URL provided, using ${JDK_URL}"
  BIN_URL="${JDK_URL}"
else
  version_tag="${JAVA_RUNTIME_VERSION}"
  version_no_prefix="${version_tag#jdk-}"
  version_no_prefix="${version_no_prefix#jre-}"
  major="${version_no_prefix%%[^0-9]*}"
  if [ -z "${major}" ]; then
    echo "Unable to derive Temurin major from JAVA_RUNTIME_VERSION=${JAVA_RUNTIME_VERSION}" >&2
    exit 1
  fi
  api_url="https://api.github.com/repos/adoptium/temurin${major}-binaries/releases/tags/${version_tag}"
  echo "Querying GitHub API: ${api_url}"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header="Authorization: token ${GITHUB_TOKEN}"
  else
    auth_header=""
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to parse GitHub API responses" >&2
    exit 1
  fi
  json="$(curl -sSL -H "$auth_header" "$api_url")"
  bin_pattern="^OpenJDK${major}U-jdk_x64_linux_hotspot_.*\\.tar\\.gz$"
  sha_pattern="^OpenJDK${major}U-jdk_x64_linux_hotspot_.*\\.tar\\.gz\\.sha256\\.txt$"
  BIN_URL="$(echo "$json" | jq -r --arg pat "$bin_pattern" '.assets[] | select(.name | test($pat)) | .browser_download_url' | head -n1 || true)"
  SHA_URL="$(echo "$json" | jq -r --arg pat "$sha_pattern" '.assets[] | select(.name | test($pat)) | .browser_download_url' | head -n1 || true)"
fi

if [ -z "$BIN_URL" ] || [ "$BIN_URL" = "null" ]; then
  echo "Could not resolve Temurin binary URL. Provide JAVA_RUNTIME_VERSION or JDK_URL explicitly." >&2
  exit 1
fi

echo "Resolved BIN_URL=${BIN_URL}"
[ -n "$SHA_URL" ] && echo "Resolved SHA_URL=${SHA_URL}" || echo "No SHA asset found via API"

echo "Downloading runtime archive..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 -o "$bin_tar" "$BIN_URL"
else
  wget -O "$bin_tar" "$BIN_URL"
fi

if [ "$skip_flag" != "true" ]; then
  sha_value=""
  if [ -n "${JDK_SHA256:-}" ]; then
    sha_value="${JDK_SHA256}"
  elif [ -n "$SHA_URL" ] && [ "$SHA_URL" != "null" ]; then
    echo "Downloading sha file..."
    if command -v curl >/dev/null 2>&1; then
      curl -fL --retry 3 -o "$sha_tmp" "$SHA_URL"
    else
      wget -O "$sha_tmp" "$SHA_URL"
    fi
    sha_value="$(grep -Eo '^[0-9a-f]{64}' "$sha_tmp" | head -n1 || true)"
  fi
  if [ -z "$sha_value" ]; then
    echo "Checksum enforcement enabled but no SHA data available" >&2
    exit 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum binary missing while checksum enforcement is required" >&2
    exit 1
  fi
  printf '%s  %s\n' "$sha_value" "$bin_tar" > "$sha_file"
  sha256sum -c "$sha_file"
else
  echo "SKIP_SHA_CHECKS=true -> not verifying JRE download"
fi

echo "Extracting runtime into ${runtime_dir}"
rm -rf "$runtime_dir"
mkdir -p "$runtime_dir"
tar -xzf "$bin_tar" -C "$runtime_dir" --strip-components=1
chown -R "${UID}:${GID}" "$runtime_dir" || true

echo "---fetch-temurin: finished---"

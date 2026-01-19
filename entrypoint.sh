#!/usr/bin/env bash
set -euo pipefail

log() { echo "[UT2004] $*"; }

UT2004_USER="ut2004"

: "${CONFIG_DIR:=/config}"
: "${SERVER_PORT:=7777}"
: "${SERVER_ARGS:=}"
: "${UT2004_DOWNLOAD_URL:=https://s3.amazonaws.com/ut2004-files/dedicated-server-3339-bonuspack.tar.gz}"
: "${DEFAULT_MAP:=DM-Rankin}"
: "${DEFAULT_GAME:=XGame.xDeathMatch}"

ensure_dirs() {
  mkdir -p "${CONFIG_DIR}"
}

download_and_extract_assets() {
  local marker_file="${CONFIG_DIR}/.assets-downloaded"
  local server_dir="${CONFIG_DIR}/ut-server"
  local bin_path="${server_dir}/System/ucc-bin"
  
  # Check if assets are already downloaded
  if [[ -f "${marker_file}" ]] && [[ -d "${server_dir}" ]] && [[ -f "${bin_path}" ]] && [[ -x "${bin_path}" ]]; then
    log "Game assets already downloaded, skipping download."
    return 0
  fi

  log "Downloading UT2004 dedicated server assets..."
  log "  URL: ${UT2004_DOWNLOAD_URL}"
  
  local tmp_dir="/tmp/ut2004-download"
  mkdir -p "${tmp_dir}"
  
  # Download the archive
  curl -fsSL "${UT2004_DOWNLOAD_URL}" -o "${tmp_dir}/ut2004-server.tar.gz"
  
  log "Extracting assets..."
  # Extract the archive
  tar -xzf "${tmp_dir}/ut2004-server.tar.gz" -C "${tmp_dir}"
  
  # The archive contains files under ./ut-server (or ut-server), so we need to handle that
  if [[ -d "${tmp_dir}/ut-server" ]]; then
    # Remove existing directory if it exists
    rm -rf "${server_dir}"
    # Move the extracted directory to the home location
    mv "${tmp_dir}/ut-server" "${server_dir}"
  elif [[ -d "${tmp_dir}/./ut-server" ]]; then
    # Handle case where archive has ./ut-server path
    rm -rf "${server_dir}"
    mv "${tmp_dir}/./ut-server" "${server_dir}"
  else
    log "ERROR: Expected 'ut-server' directory not found in archive"
    log "Contents of extracted archive:"
    ls -la "${tmp_dir}" || true
    rm -rf "${tmp_dir}"
    exit 1
  fi
  
  # Create marker file to indicate successful download
  touch "${marker_file}"
  
  # Cleanup
  rm -rf "${tmp_dir}"
  
  # Set ownership and ensure binary is executable
  chown -R "${UT2004_USER}:${UT2004_USER}" "${server_dir}" "${marker_file}"
  if [[ -f "${server_dir}/System/ucc-bin" ]]; then
    chmod +x "${server_dir}/System/ucc-bin"
  fi
  if [[ -f "${server_dir}/System/ucc" ]]; then
    chmod +x "${server_dir}/System/ucc"
  fi
  
  log "Assets downloaded and extracted successfully."
}

find_ut2004_bin() {
  local candidates=(
    "${CONFIG_DIR}/ut-server/System/ucc-bin"
    "${CONFIG_DIR}/ut-server/System/ucc"
  )

  for c in "${candidates[@]}"; do
    if [[ -x "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done

  return 1
}

patch_master_server() {
  local server_dir="${CONFIG_DIR}/ut-server"
  local ini_file="${server_dir}/System/UT2004.ini"
  
  # Try alternative locations if UT2004.ini doesn't exist
  if [[ ! -f "${ini_file}" ]]; then
    ini_file="${server_dir}/System/Default.ini"
  fi
  
  if [[ ! -f "${ini_file}" ]]; then
    log "Warning: Could not find UT2004.ini or Default.ini, skipping master server patch"
    return 0
  fi
  
  log "Patching master server configuration in ${ini_file}"
  
  # Create a temporary file for the patched ini
  local tmp_file="${ini_file}.tmp"
  
  # Use sed and awk to process the ini file:
  # First, remove all existing MasterServerList entries in the section
  # Then add the new entry after the section header
  sed '/^\[IpDrv\.MasterServerLink\]/,/^\[/{
    /^MasterServerList/d
  }' "${ini_file}" > "${tmp_file}.sed"
  
  # Now add the new MasterServerList entry right after [IpDrv.MasterServerLink]
  awk '{
    print
    if (/^\[IpDrv\.MasterServerLink\]/) {
      print "MasterServerList=(Address=\"utmaster.openspy.net\",Port=28902)"
    }
  }' "${tmp_file}.sed" > "${tmp_file}"
  
  rm -f "${tmp_file}.sed"
  
  # Replace original file with patched version
  mv "${tmp_file}" "${ini_file}"
  
  # Set ownership
  chown "${UT2004_USER}:${UT2004_USER}" "${ini_file}"
  
  log "Master server configuration patched successfully"
}

main() {
  ensure_dirs

  # Best-effort ownership fix for mounted volume
  chown -R "${UT2004_USER}:${UT2004_USER}" "${CONFIG_DIR}" \
    >/dev/null 2>&1 || true

  download_and_extract_assets

  patch_master_server

  local bin
  if ! bin="$(find_ut2004_bin)"; then
    log "ERROR: Could not find UT2004 binary under ${CONFIG_DIR}/ut-server/System"
    log "Contents of ${CONFIG_DIR}:"
    ls -la "${CONFIG_DIR}" || true
    if [[ -d "${CONFIG_DIR}/ut-server" ]]; then
      log "Contents of ${CONFIG_DIR}/ut-server:"
      ls -la "${CONFIG_DIR}/ut-server" || true
      if [[ -d "${CONFIG_DIR}/ut-server/System" ]]; then
        log "Contents of ${CONFIG_DIR}/ut-server/System:"
        ls -la "${CONFIG_DIR}/ut-server/System" || true
      else
        log "ERROR: System directory does not exist"
      fi
    else
      log "ERROR: ut-server directory does not exist"
    fi
    exit 1
  fi

  log "Starting Unreal Tournament 2004"
  log "  Server dir:  ${CONFIG_DIR}/ut-server"
  log "  Config dir:  ${CONFIG_DIR}"
  log "  Port (UDP):  ${SERVER_PORT}"

  # Change to the System directory for proper execution (UT2004 expects to run from System/)
  cd "${CONFIG_DIR}/ut-server/System"

  # Build server command
  # If SERVER_ARGS is empty, use default map and game type
  # If SERVER_ARGS doesn't look like a map (starts with DM-, CTF-, ONS-, etc.), append it to default map
  local map_args
  if [[ -z "${SERVER_ARGS}" ]]; then
    map_args="${DEFAULT_MAP}?Game=${DEFAULT_GAME}"
    log "  Using default map: ${map_args}"
    log "  (Set SERVER_ARGS environment variable to customize)"
  elif [[ "${SERVER_ARGS}" =~ ^(DM-|CTF-|ONS-|BR-|DOM-|AS-|VCTF-|WAR-) ]]; then
    # Looks like a map name, use it as-is
    map_args="${SERVER_ARGS}"
    log "  Using custom map: ${map_args}"
  else
    # Looks like additional parameters, append to default map
    map_args="${DEFAULT_MAP}?Game=${DEFAULT_GAME}?${SERVER_ARGS}"
    log "  Using default map with custom parameters: ${map_args}"
  fi

  exec gosu "${UT2004_USER}" \
    "${bin}" \
    server \
    ${map_args} \
    -port="${SERVER_PORT}"
}

main "$@"

#!/bin/bash

# Dispatch to flavor-specific start-server implementations based on IMAGE_FLAVOR.
#
# Supported values:
#   - download_official (default): Temurin-based implementation
#   - firefox: same as download_official, Firefox/Fluxbox focused
#   - legacy: legacy implementation using ich777/runtimes basicjre tarball

flavor="${IMAGE_FLAVOR:-download_official}"
DATA_DIR="${DATA_DIR:-/jDownloader2}"
BACKUP_ROOT="${DATA_DIR}/backups"
BROWSER_CMDLINE_CFG="${DATA_DIR}/cfg/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json"
BROWSER_CMDLINE_BACKUP_REL="jdownloader2/cfg/$(basename "${BROWSER_CMDLINE_CFG}")"
BROWSER_CMDLINE_BACKUP="${BACKUP_ROOT}/${BROWSER_CMDLINE_BACKUP_REL}"

backup_path() {
	local src="$1"
	local rel="$2"
	local mode="$3" # "move" or "copy"

	[ -e "${src}" ] || return 0

	local dest="${BACKUP_ROOT}/${rel}"
	mkdir -p "$(dirname "${dest}")"

	case "${mode}" in
		move)
			mv "${src}" "${dest}"
			;;
		copy|*)
			if [ -d "${src}" ]; then
				cp -a "${src}"/. "${dest}"/
			else
				cp -a "${src}" "${dest}"
			fi
			;;
	esac
}

backup_fluxbox_config() {
	if [ -d "/etc/.fluxbox" ]; then
		backup_path "/etc/.fluxbox" "etc/.fluxbox" "copy"
	fi
}

# Always snapshot current Fluxbox config into the data volume so
# user customizations can be restored manually after flavor changes.
backup_fluxbox_config

case "${flavor}" in
  legacy)
    # Ensure the legacy script only sees its own jre* runtime. Remove any JDK runtimes created by other flavors.
    if [ -d "${DATA_DIR}/runtime" ]; then
      if compgen -G "${DATA_DIR}/runtime/jdk*" > /dev/null; then
        rm -rf "${DATA_DIR}/runtime"/jdk*
      fi
    fi

    if [ -f "${BROWSER_CMDLINE_CFG}" ]; then
      backup_path "${BROWSER_CMDLINE_CFG}" "${BROWSER_CMDLINE_BACKUP_REL}" "move"
      echo "---------------------------------------------------------------------------------------------"
      echo "Browser-based captcha solver config is not supported in 'legacy' flavor."
      echo "The config has been removed from active use and backed up to:"
      echo "  ${BROWSER_CMDLINE_BACKUP}"
      echo "---------------------------------------------------------------------------------------------"
    fi

    exec /opt/scripts/start-server-legacy.sh
    ;;
  firefox)
	echo "---start-server: using firefox implementation (IMAGE_FLAVOR=firefox)---"
	# Ensure default browser captcha solver config is in place
	if [ ! -d ${DATA_DIR}/cfg ]; then
		mkdir ${DATA_DIR}/cfg
	fi
	if [ ! -f "${BROWSER_CMDLINE_CFG}" ]; then
		if [ -f "/opt/jdownloader-defaults/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json" ]; then
			cp "/opt/jdownloader-defaults/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json" \
			"${BROWSER_CMDLINE_CFG}"
		fi
	fi
	exec /opt/scripts/start-server-download_official.sh
	;;
  download_official|*)
	if [ -f "${BROWSER_CMDLINE_CFG}" ]; then
		backup_path "${BROWSER_CMDLINE_CFG}" "${BROWSER_CMDLINE_BACKUP_REL}" "move"
		echo "---------------------------------------------------------------------------------------------"
		echo "---WARNING: ${flavor} flavor does not support browser captcha solver, removing invalid config!---"
		echo "---A backup of the removed config was stored at: ${BROWSER_CMDLINE_BACKUP}---"
		echo "---------------------------------------------------------------------------------------------"
	fi
	echo "---start-server: using official-download implementation (IMAGE_FLAVOR=${flavor})---"
	exec /opt/scripts/start-server-download_official.sh
	;;
esac

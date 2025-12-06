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

requested_runtime="${JAVA_RUNTIME_VERSION:?JAVA_RUNTIME_VERSION env var must be set}"
requested_release="${requested_runtime#jdk-}"
requested_release="${requested_release#jre-}"
release_file="${DATA_DIR}/runtime/release"
runtime_java="${DATA_DIR}/runtime/bin/java"
install_runtime="false"

echo "---Ensuring runtime ${requested_runtime} is installed---"
if [ ! -x "${runtime_java}" ]; then
	echo "---Runtime binary missing---"
	install_runtime="true"
elif [ ! -f "${release_file}" ]; then
	echo "---Runtime release file missing---"
	install_runtime="true"
else
	installed_runtime="$(grep -E '^JAVA_RUNTIME_VERSION=' "${release_file}" | head -n1 | sed -nE 's/.*="([^"]+)".*/\1/p' || true)"
	if [ -z "${installed_runtime}" ]; then
		echo "---Unable to read JAVA_RUNTIME_VERSION from release file---"
		install_runtime="true"
	elif [ "${installed_runtime}" != "${requested_release}" ]; then
		echo "---Installed runtime (${installed_runtime}) differs from requested ${requested_release}---"
		install_runtime="true"
	else
		echo "---Runtime ${installed_runtime} already installed---"
	fi
fi

if [ "${install_runtime}" = "true" ]; then
	echo "---Downloading runtime (${requested_runtime}) via fetch-temurin.sh---"
	/opt/scripts/fetch-temurin.sh || {
		echo "---Failed to fetch Temurin runtime---"; sleep infinity; }
fi

if [ ! -x "${runtime_java}" ]; then
	echo "---------------------------------------------------------------------------------------------"
	echo "---Runtime binary missing after installation attempt, putting server in sleep mode!---"
	echo "---------------------------------------------------------------------------------------------"
	sleep infinity
fi

echo "---Checking for 'jDownloader.jar'---"
if [ ! -f ${DATA_DIR}/JDownloader.jar ]; then
	echo "---'jDownloader.jar' not found, copying...---"
	cd ${DATA_DIR}
	cp /tmp/JDownloader.jar ${DATA_DIR}/JDownloader.jar
	if [ ! -f ${DATA_DIR}/JDownloader.jar ]; then
		echo "--------------------------------------------------------------------------------------"
		echo "---Something went wrong can't copy 'jDownloader.jar', putting server in sleep mode!---"
		echo "--------------------------------------------------------------------------------------"
		sleep infinity
	fi
else
	echo "---'jDownloader.jar' folder found---"
fi

echo "---Preparing Server---"

echo "---Checking libraries---"
if [ ! -d ${DATA_DIR}/libs ]; then
	mkdir ${DATA_DIR}/libs
fi
missing_libs=true
if [ -f ${DATA_DIR}/libs/sevenzipjbinding1509Linux.jar ] || \
	[ -f ${DATA_DIR}/libs/sevenzipjbinding1509.jar ] || \
	[ -f ${DATA_DIR}/libs/sevenzipjbinding-Linux-amd64.jar ] || \
	[ -f ${DATA_DIR}/libs/sevenzipjbinding.jar ] || \
	[ -f ${DATA_DIR}/libs/sevenzipjbinding-AllLinux.jar ]; then
	missing_libs=false
fi

if [ "${missing_libs}" = "true" ]; then
	echo "---Sevenzip libraries not found; checking /tmp/lib for jar files---"
	if [ -d /tmp/lib ]; then
		found_jar=false
		for jar_file in /tmp/lib/*.jar; do
			if [ ! -e "${jar_file}" ]; then
				break
			fi
			found_jar=true
			echo "---Copying sevenzip library: ${jar_file} -> ${DATA_DIR}/libs/---"
			cp "${jar_file}" "${DATA_DIR}/libs/" || echo "---Warning: failed to copy ${jar_file}---"
		done
		if [ "${found_jar}" = "false" ]; then
			echo "---Warning: /tmp/lib exists but contains no .jar files; continuing without sevenzip libraries---"
		fi
	else
		echo "---Warning: /tmp/lib not found; continuing without sevenzip libraries---"
	fi
else
	echo "---Sevenzip libraries already present in ${DATA_DIR}/libs---"
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
if [ -z "${CUSTOM_RES_W}" ]; then
	CUSTOM_RES_W=1024
fi
if [ -z "${CUSTOM_RES_H}" ]; then
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

if [ ! -f "${DATA_DIR}/cfg/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json" ]; then
    if [ -f "/opt/jdownloader-defaults/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json" ]; then
        cp "/opt/jdownloader-defaults/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json" \
           "${DATA_DIR}/cfg/org.jdownloader.captcha.v2.solver.browser.BrowserCaptchaSolverConfig.browsercommandline.json"
    fi
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
eval ${runtime_java} ${EXTRA_JVM_PARAMS} -jar ${DATA_DIR}/JDownloader.jar

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
if [ -z "$(find ${DATA_DIR}/runtime -name jre*)" ]; then
    if [ "${RUNTIME_NAME}" == "basicjre" ]; then
    	echo "---Downloading and installing Runtime (basicjre) via fetch-temurin.sh---"
    	# Use helper script to discover/download/verify Temurin. You can override via JDK_URL/JDK_SHA256.
    	/opt/scripts/fetch-temurin.sh || {
    		echo "---Failed to fetch Temurin runtime---"; sleep infinity; }
    else
    	if [ ! -d ${DATA_DIR}/runtime/${RUNTIME_NAME} ]; then
        	echo "---------------------------------------------------------------------------------------------"
        	echo "---Runtime not found in folder 'runtime' please check again! Putting server in sleep mode!---"
        	echo "---------------------------------------------------------------------------------------------"
        	sleep infinity
        fi
    fi
else
	echo "---Runtime found---"
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
# Determine runtime directory name (prefer extracted jre* directory)
rt_dir=$(find ${DATA_DIR}/runtime -maxdepth 1 -type d -name "jre*" | head -n1 || true)
if [ -n "$rt_dir" ]; then
	export RUNTIME_NAME="$(basename "$rt_dir")"
else
	# fallback: pick first directory under runtime
	export RUNTIME_NAME="$(ls -d ${DATA_DIR}/runtime/* | head -n1 | xargs -n1 basename 2>/dev/null || echo "")"
fi

echo "---Checking libraries---"
if [ ! -d ${DATA_DIR}/libs ]; then
	mkdir ${DATA_DIR}/libs
fi
if [ ! -f ${DATA_DIR}/libs/sevenzipjbinding1509Linux.jar ]; then
	cd ${DATA_DIR}/libs
	if [ ! -f ${DATA_DIR}/libs/lib.tar.gz ]; then
		cp /tmp/lib.tar.gz ${DATA_DIR}/libs/lib.tar.gz
	fi
    if [ -f ${DATA_DIR}/libs/lib.tar.gz ]; then
    	tar -xf ${DATA_DIR}/libs/lib.tar.gz
    	rm ${DATA_DIR}/libs/lib.tar.gz
	fi
else
	echo "---Libraries found!---"
fi
if [ ! -f ${DATA_DIR}/libs/sevenzipjbinding1509.jar ]; then
	cd ${DATA_DIR}/libs
	if [ ! -f ${DATA_DIR}/libs/lib.tar.gz ]; then
		cp /tmp/lib.tar.gz ${DATA_DIR}/libs/lib.tar.gz
	fi
    if [ -f ${DATA_DIR}/libs/lib.tar.gz ]; then
    	tar -xf ${DATA_DIR}/libs/lib.tar.gz
    	rm ${DATA_DIR}/libs/lib.tar.gz
	fi
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
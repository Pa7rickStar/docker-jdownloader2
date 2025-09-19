FROM ich777/novnc-baseimage

LABEL org.opencontainers.image.authors="admin@minenet.at"
LABEL org.opencontainers.image.source="https://github.com/Pa7rickStar/docker-jdownloader2"

RUN export TZ=Europe/Rome && \
	apt-get update && \
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
	echo $TZ > /etc/timezone && \
	apt-get -y install --no-install-recommends fonts-takao netcat-traditional wget curl && \
	apt-get -y install ffmpeg unzip && \
	echo "ko_KR.UTF-8 UTF-8" >> /etc/locale.gen && \ 
	echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen && \
	locale-gen && \
	rm -rf /var/lib/apt/lists/* && \
	sed -i '/    document.title =/c\    document.title = "jDownloader2 - noVNC";' /usr/share/novnc/app/ui.js && \
	rm /usr/share/novnc/app/images/icons/*


ENV DATA_DIR=/jDownloader2
ENV CUSTOM_RES_W=1280
ENV CUSTOM_RES_H=1024
ENV CUSTOM_DEPTH=16
ENV NOVNC_PORT=8080
ENV RFB_PORT=5900
ENV TURBOVNC_PARAMS="-securitytypes none"
ENV RUNTIME_NAME="basicjre"
ENV UMASK=000
ENV CONNECTED_CONTAINERS=""
ENV CONNECTED_CONTAINERS_TIMEOUT=60
ENV UID=99
ENV GID=100
ENV DATA_PERM=770
ENV USER="jdownloader"

RUN mkdir $DATA_DIR && \
	useradd -d $DATA_DIR -s /bin/bash $USER && \
	chown -R $USER $DATA_DIR && \
	ulimit -n 2048

ADD /scripts/ /opt/scripts/
COPY /icons/* /usr/share/novnc/app/images/icons/
RUN set -eux; \
	echo "Downloading JDownloader.jar"; \
	wget -O /tmp/JDownloader.jar "https://installer.jdownloader.org/JDownloader.jar"; \
	ls -l /tmp/JDownloader.jar

# Download 7-Zip-JBinding (used previously via JD/lib.tar.gz)
# You can override SEVENZIP_VERSION at build time with --build-arg
ARG SEVENZIP_VERSION=16.02-2.01
ARG SEVENZIP_FILENAME=sevenzipjbinding-${SEVENZIP_VERSION}-Linux-amd64.zip
ARG SEVENZIP_URL="https://sourceforge.net/projects/sevenzipjbind/files/7-Zip-JBinding/${SEVENZIP_VERSION}/${SEVENZIP_FILENAME}/download?use_mirror=master"
RUN set -eux; \
	echo "Downloading ${SEVENZIP_FILENAME} from ${SEVENZIP_URL}"; \
	wget -O /tmp/${SEVENZIP_FILENAME} "${SEVENZIP_URL}"; \
	# unzip will create multiple items; extract to /tmp
		unzip -q /tmp/${SEVENZIP_FILENAME} -d /tmp/ || (echo "unzip failed" && ls -la /tmp && false); \
		rm -f /tmp/${SEVENZIP_FILENAME}; \
		# Create a lib.tar.gz in /tmp to preserve compatibility with startup scripts
		if [ -d /tmp/lib ]; then \
			tar -C /tmp -czf /tmp/lib.tar.gz lib; \
		fi; \
		# Keep only /tmp/lib, /tmp/lib.tar.gz and /tmp/JDownloader.jar (remove everything else in /tmp)
		find /tmp -maxdepth 1 -mindepth 1 ! -name lib ! -name lib.tar.gz ! -name JDownloader.jar -exec rm -rf {} + || true

	# Runtime JDK is downloaded at container startup (Temurin default) by `start-server.sh`.
COPY /conf/ /etc/.fluxbox/
RUN chmod -R 770 /opt/scripts/ && \
	chown -R ${UID}:${GID} /mnt && \
	chmod -R 770 /mnt

EXPOSE 8080

#Server Start
ENTRYPOINT ["/opt/scripts/start.sh"]
FROM ich777/novnc-baseimage

LABEL org.opencontainers.image.authors="admin@minenet.at"
# LABEL org.opencontainers.image.source="https://github.com/ich777/docker-jdownloader2"
# Temporary for testing:
LABEL org.opencontainers.image.source="https://github.com/Pa7rickStar/docker-jdownloader2"

RUN export TZ=Europe/Rome && \
	apt-get update && \
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
	echo $TZ > /etc/timezone && \
	apt-get -y install --no-install-recommends fonts-takao netcat-traditional wget curl jq && \
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
ENV UMASK=000
ENV CONNECTED_CONTAINERS=""
ENV CONNECTED_CONTAINERS_TIMEOUT=60
ENV UID=99
ENV GID=100
ENV DATA_PERM=770
ENV USER="jdownloader"
ARG JRE_VERSION="jdk-24.0.2+12"
ARG JD_SHA256=""
ARG FORCE_SHA_CHECK=false
ARG GITHUB_TOKEN=""
ENV JRE_VERSION=${JRE_VERSION}
ENV JD_SHA256=${JD_SHA256}
ENV FORCE_SHA_CHECK=${FORCE_SHA_CHECK}
ENV GITHUB_TOKEN=${GITHUB_TOKEN}

RUN mkdir $DATA_DIR && \
	useradd -d $DATA_DIR -s /bin/bash $USER && \
	chown -R $USER $DATA_DIR && \
	ulimit -n 2048

ADD /scripts/ /opt/scripts/
COPY /icons/* /usr/share/novnc/app/images/icons/
RUN set -eux; \
	echo "Preparing JDownloader installer download and optional SHA256 verification"; \
	# If JD_SHA256 is empty, try to fetch it from the official support article
	if [ -z "$JD_SHA256" ]; then \
		echo "JD_SHA256 is empty; attempting to fetch from support page"; \
		page_url="https://support.jdownloader.org/de/knowledgebase/article/install-jdownloader-on-nas-and-embedded-devices"; \
		tmp_html="/tmp/jd_support.html"; \
		if curl -fsSL "$page_url" -o "$tmp_html"; then \
			extract_sha() { \
				_file="$1"; \
				line="$(grep -i 'sha256' "$_file" | head -n1 || true)"; \
				if [ -n "$line" ]; then \
					sha="$(echo "$line" | sed -nE 's/.*([A-Fa-f0-9]{64}).*/\1/p' | tr '[:upper:]' '[:lower:]' | head -n1 || true)"; \
					[ -n "$sha" ] && { printf '%s' "$sha"; return 0; } ; \
				fi; \
				sha="$(grep -ioE '[a-f0-9]{64}' "$_file" | head -n1 || true)"; \
				[ -n "$sha" ] && { printf '%s' "$(echo \"$sha\" | tr '[:upper:]' '[:lower:]')"; return 0; } ; \
				return 1; \
			}; \
			jd_hash="$(extract_sha "$tmp_html" || true)"; \
			if [ -n "$jd_hash" ]; then \
				JD_SHA256="$jd_hash"; \
				echo "Extracted JD_SHA256=$JD_SHA256"; \
			else \
				echo "No SHA256 hash found on support page"; \
			fi; \
		else \
			echo "Failed to download support page; continuing without JD_SHA256"; \
		fi; \
	else \
		echo "JD_SHA256 provided at build time: $JD_SHA256"; \
	fi; \
	echo "Downloading JDownloader.jar"; \
	wget -O /tmp/JDownloader.jar "https://installer.jdownloader.org/JDownloader.jar"; \
	ls -l /tmp/JDownloader.jar; \
	# Verify downloaded file if JD_SHA256 is not empty
	if [ -n "$JD_SHA256" ]; then \
		echo "Verifying JDownloader.jar SHA256"; \
		calc="$(sha256sum /tmp/JDownloader.jar | awk '{print $1}')" || calc=""; \
		if [ "$(echo "$calc" | tr '[:upper:]' '[:lower:]')" != "$(echo "$JD_SHA256" | tr '[:upper:]' '[:lower:]')" ]; then \
			echo "SHA256 mismatch: expected $JD_SHA256 got $calc"; \
			if [ "$FORCE_SHA_CHECK" = "true" ] || [ "$FORCE_SHA_CHECK" = "1" ]; then \
				echo "FORCE_SHA_CHECK is set -> failing build"; \
				exit 1; \
			else \
				echo "Warning: checksum mismatch but FORCE_SHA_CHECK not set; continuing"; \
			fi; \
		else \
			echo "Checksum matches"; \
		fi; \
	else \
		echo "No JD_SHA256 available to verify against"; \
	fi

RUN set -eux; \
	echo "Resolving sevenzipjbinding release via SourceForge best_release.json"; \
	info_json="/tmp/seven_best.json"; \
	if curl -fsSL -H "Accept: application/json" "https://sourceforge.net/projects/sevenzipjbind/best_release.json" -o "$info_json"; then \
		pf="linux"; \
		filename="$(jq -r --arg p "$pf" '.platform_releases[$p].filename // .release.filename' "$info_json")"; \
		saved_name="$(basename "${filename}")"; \
		saved_path="/tmp/${saved_name}"; \
		url="$(jq -r --arg p "$pf" '.platform_releases[$p].url // .release.url' "$info_json")"; \
		expected_md5="$(jq -r --arg p "$pf" '.platform_releases[$p].md5sum // .release.md5sum // empty' "$info_json")"; \
		filename="${saved_name}"; \
	else \
		echo "Failed to fetch best_release.json; falling back to a conservative default"; \
		filename="sevenzipjbinding-16.02-2.01-Linux-amd64.zip"; \
		url="https://sourceforge.net/projects/sevenzipjbind/files/7-Zip-JBinding/16.02-2.01/${filename}/download?use_mirror=master"; \
		expected_md5=""; \
	fi; \
	echo "Downloading ${filename} from ${url}"; \
		wget -O "${saved_path}" "${url}"; \
	if [ -n "${expected_md5:-}" ]; then \
		echo "Verifying ${filename} against md5 ${expected_md5}"; \
			actual_md5="$(md5sum "${saved_path}" | awk '{print $1}' || true)"; \
		if [ -z "$actual_md5" ]; then \
			echo "Failed to calculate md5 of /tmp/${filename}"; exit 1; \
		fi; \
		if [ "$(echo "$actual_md5" | tr '[:upper:]' '[:lower:]')" != "$(echo "$expected_md5" | tr '[:upper:]' '[:lower:]')" ]; then \
			echo "MD5 mismatch for ${filename}: expected ${expected_md5} got ${actual_md5}"; \
			if [ "$FORCE_SHA_CHECK" = "true" ] || [ "$FORCE_SHA_CHECK" = "1" ]; then \
				echo "FORCE_SHA_CHECK is set -> failing build"; \
				exit 1; \
			else \
				echo "Warning: MD5 mismatch but FORCE_SHA_CHECK not set; continuing"; \
			fi; \
		else \
			echo "MD5 verified"; \
		fi; \
	else \
		echo "No expected md5 provided; skipping md5 verification"; \
	fi; \
		unzip -q "${saved_path}" -d /tmp/ || (echo "unzip failed" && ls -la /tmp && false); \
		rm -f "${saved_path}"; \
	# Keep only /tmp/lib, /tmp/lib.tar.gz and /tmp/JDownloader.jar (remove everything else in /tmp)
	find /tmp -maxdepth 1 -mindepth 1 ! -name lib ! -name lib.tar.gz ! -name JDownloader.jar -exec rm -rf {} + || true

COPY /conf/ /etc/.fluxbox/
RUN chmod -R 770 /opt/scripts/ && \
	chown -R ${UID}:${GID} /mnt && \
	chmod -R 770 /mnt

EXPOSE 8080

#Server Start
ENTRYPOINT ["/opt/scripts/start.sh"]

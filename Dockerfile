FROM ich777/novnc-baseimage

LABEL org.opencontainers.image.authors="admin@minenet.at"
# LABEL org.opencontainers.image.source="https://github.com/ich777/docker-jdownloader2"
# Temporary for testing:
LABEL org.opencontainers.image.source="https://github.com/Pa7rickStar/docker-jdownloader2"

RUN export TZ=Europe/Rome && \
	apt-get update && apt-get upgrade -y && \
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
	echo $TZ > /etc/timezone && \
	apt-get -y install --no-install-recommends fonts-takao netcat-traditional wget curl jq nano xterm firefox-esr && \
	apt-get -y install ffmpeg unzip && \
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
ENV SKIP_SHA_CHECKS=false
ENV JAVA_RUNTIME_VERSION="jdk-24.0.2+12"
ENV JD_DOWNLOAD_URL="https://installer.jdownloader.org/JDownloader.jar"
ENV JD_SHA_PAGE_URL="https://support.jdownloader.org/de/knowledgebase/article/install-jdownloader-on-nas-and-embedded-devices"
ENV JD_SHA256=""
ENV SEVENZIP_BEST_URL="https://sourceforge.net/projects/sevenzipjbind/best_release.json"
ENV SEVENZIP_FALLBACK_URL="https://sourceforge.net/projects/sevenzipjbind/files/7-Zip-JBinding/16.02-2.01/sevenzipjbinding-16.02-2.01-Linux-amd64.zip/download?use_mirror=master"
ENV SEVENZIP_MD5=""
ENV GITHUB_TOKEN=""
ENV FIREFOX_EXT_URL="https://extensions.jdownloader.org/firefox.xpi"

RUN mkdir -p $DATA_DIR/firefox-home && \
	useradd -d $DATA_DIR -s /bin/bash $USER && \
	chown -R $USER $DATA_DIR && \
	ulimit -n 2048

RUN mkdir -p /usr/lib/firefox-esr/distribution/extensions && \
	wget -O /usr/lib/firefox-esr/distribution/extensions/jid1-OY8Xu5BsKZQa6A@jetpack.xpi "${FIREFOX_EXT_URL}"

ADD /scripts/ /opt/scripts/
COPY /icons/* /usr/share/novnc/app/images/icons/
RUN set -eux; \
	skip_flag="$(printf '%s' "${SKIP_SHA_CHECKS}" | tr '[:upper:]' '[:lower:]')"; \
	jd_expected="${JD_SHA256}"; \
	jd_support_tmp="/tmp/jd_support.html"; \
	jd_jar="/tmp/JDownloader.jar"; \
	if [ "$skip_flag" != "true" ]; then \
		if [ -z "$jd_expected" ]; then \
			echo "JD_SHA256 empty; attempting to scrape ${JD_SHA_PAGE_URL}"; \
			if curl -fsSL "${JD_SHA_PAGE_URL}" -o "$jd_support_tmp"; then \
				extract_sha() { \
					_file="$1"; \
					line="$(grep -i 'sha256' "$_file" | head -n1 || true)"; \
					if [ -n "$line" ]; then \
						sha="$(echo "$line" | sed -nE 's/.*([A-Fa-f0-9]{64}).*/\1/p' | tr '[:upper:]' '[:lower:]' | head -n1 || true)"; \
						[ -n "$sha" ] && { printf '%s' "$sha"; return 0; }; \
					fi; \
					hex="$(grep -ioE '[a-f0-9]{64}' "$_file" | head -n1 || true)"; \
					[ -n "$hex" ] && { printf '%s' "$(echo "$hex" | tr '[:upper:]' '[:lower:]')"; return 0; }; \
					return 1; \
				}; \
				jd_scraped="$(extract_sha "$jd_support_tmp" || true)"; \
				if [ -n "$jd_scraped" ]; then \
					jd_expected="$jd_scraped"; \
					echo "Scraped JD_SHA256=$jd_expected"; \
				else \
					echo "Failed to scrape JD checksum"; \
				fi; \
			else \
				echo "Could not download JD SHA page"; \
			fi; \
		else \
			echo "JD_SHA256 provided via environment"; \
		fi; \
		if [ -z "$jd_expected" ]; then \
			echo "Checksum enforcement enabled but no JD_SHA256 available"; \
			exit 1; \
		fi; \
	else \
		echo "SKIP_SHA_CHECKS=true -> not verifying JDownloader.jar"; \
	fi; \
	echo "Downloading JDownloader.jar from ${JD_DOWNLOAD_URL}"; \
	wget -O "$jd_jar" "${JD_DOWNLOAD_URL}"; \
	ls -l "$jd_jar"; \
	if [ "$skip_flag" != "true" ]; then \
		calc="$(sha256sum "$jd_jar" | awk '{print $1}' || true)"; \
		if [ -z "$calc" ]; then \
			echo "Failed to compute SHA256 for JDownloader.jar"; \
			exit 1; \
		fi; \
		normal_calc="$(printf '%s' "$calc" | tr '[:upper:]' '[:lower:]')"; \
		normal_expected="$(printf '%s' "$jd_expected" | tr '[:upper:]' '[:lower:]')"; \
		if [ "$normal_calc" != "$normal_expected" ]; then \
			echo "SHA256 mismatch for JDownloader.jar (expected $normal_expected got $normal_calc)"; \
			exit 1; \
		fi; \
		echo "JDownloader.jar checksum verified"; \
	fi

RUN set -eux; \
	skip_flag="$(printf '%s' "${SKIP_SHA_CHECKS}" | tr '[:upper:]' '[:lower:]')"; \
	info_json="/tmp/seven_best.json"; \
	filename=""; \
	url=""; \
	expected_md5="${SEVENZIP_MD5}"; \
	saved_path=""; \
	if curl -fsSL -H "Accept: application/json" "${SEVENZIP_BEST_URL}" -o "$info_json"; then \
		if command -v jq >/dev/null 2>&1; then \
			platform="linux"; \
			filename_raw="$(jq -r --arg p "$platform" '.platform_releases[$p].filename // .release.filename // empty' "$info_json")"; \
			url="$(jq -r --arg p "$platform" '.platform_releases[$p].url // .release.url // empty' "$info_json")"; \
			if [ -z "$expected_md5" ] || [ "$expected_md5" = "null" ]; then \
				expected_md5="$(jq -r --arg p "$platform" '.platform_releases[$p].md5sum // .release.md5sum // empty' "$info_json")"; \
			fi; \
			if [ -n "$filename_raw" ] && [ "$filename_raw" != "null" ]; then \
				filename="$(basename "$filename_raw")"; \
			fi; \
		else \
			echo "jq missing; skipping best_release parsing"; \
		fi; \
	else \
		echo "Failed to fetch sevenzip best_release.json"; \
	fi; \
	if [ -z "$filename" ] || [ "$filename" = "null" ]; then \
		filename="$(basename "${SEVENZIP_FALLBACK_URL}")"; \
	fi; \
	if [ -z "$url" ] || [ "$url" = "null" ]; then \
		url="${SEVENZIP_FALLBACK_URL}"; \
	fi; \
	saved_path="/tmp/${filename}"; \
	mkdir -p "$(dirname "$saved_path")"; \
	echo "Downloading ${filename} from ${url}"; \
	wget -O "$saved_path" "$url"; \
	if [ "$skip_flag" != "true" ]; then \
		if [ -z "$expected_md5" ] || [ "$expected_md5" = "null" ]; then \
			echo "Checksum enforcement enabled but no MD5 available for sevenzip"; \
			exit 1; \
		fi; \
		actual_md5="$(md5sum "$saved_path" | awk '{print $1}' || true)"; \
		if [ -z "$actual_md5" ]; then \
			echo "Failed to compute MD5 for ${filename}"; \
			exit 1; \
		fi; \
		normal_md5="$(printf '%s' "$actual_md5" | tr '[:upper:]' '[:lower:]')"; \
		expected_md5="$(printf '%s' "$expected_md5" | tr '[:upper:]' '[:lower:]')"; \
		if [ "$normal_md5" != "$expected_md5" ]; then \
			echo "MD5 mismatch for ${filename} (expected $expected_md5 got $normal_md5)"; \
			exit 1; \
		fi; \
		echo "sevenzip MD5 verified"; \
	else \
		echo "SKIP_SHA_CHECKS=true -> not verifying sevenzip"; \
	fi; \
	workdir="/tmp/sevenzipjbinding"; \
    rm -rf "$workdir"; \
    mkdir -p "$workdir"; \
    unzip -q "$saved_path" -d "$workdir" || (echo "unzip failed" && ls -R "$workdir" && false); \
    rm -f "$saved_path"; \
    libdir="$(find "$workdir" -type d -name lib | head -n1 || true)"; \
    if [ -z "$libdir" ]; then \
        echo "lib directory not found under $workdir"; \
        ls -R "$workdir"; \
        exit 1; \
    fi; \
    mv "$libdir" /tmp/lib; \
    rm -rf "$workdir"; \
	find /tmp -maxdepth 1 -mindepth 1 \
		! -name 'lib' \
		! -name 'JDownloader.jar' \
		-exec rm -rf {} + || true

COPY /conf/ /etc/.fluxbox/
RUN chmod -R 770 /opt/scripts/ && \
	chown -R ${UID}:${GID} /mnt && \
	chmod -R 770 /mnt

EXPOSE 8080

#Server Start
ENTRYPOINT ["/opt/scripts/start.sh"]

# jDownloader2 in Docker optimized for Unraid
This Docker will download and install jDownloader2.

JDownloader 2 is a free, open-source download management tool with a huge community of developers that makes downloading as easy and fast as it should be. Users can start, stop or pause downloads, set bandwith limitations, auto-extract archives and much more...


>**Update Notice:** Updates will be handled through jDownloader2 directly, simply click the 'Check for Updates' in the WebGUI.


>**NOTE:** Please also check out the homepage from jDownloader: http://jdownloader.org/

## Env params
| Name | Description | Example |
| --- | --- | --- |
| CUSTOM_RES_W | Minimum of 1024 pixels (leave blank for 1024 pixels) | 1024 |
| CUSTOM_RES_H | Minimum of 768 pixels (leave blank for 768 pixels) | 768 |
| UMASK | Permissions for newly created files and folders | 000 |
| UID | User identifier used inside the container | 99 |
| GID | Group identifier used inside the container | 100 |
| SKIP_SHA_CHECKS | When `true` all checksum validation is skipped; when `false` (default) every JDownloader, sevenzip and JRE download must pass checksum validation or the build/startup aborts. | false |
| JAVA_RUNTIME_VERSION | Exact Temurin runtime tag to install. Changing this value will trigger a re-download of the matching JRE if the existing runtime version does not match. | jdk-24.0.2+12 |

### Advanced env params

The following variables are optional and usually only needed for debugging or when upstream metadata cannot be parsed correctly:

- `JD_DOWNLOAD_URL` – URL from which the container downloads `JDownloader.jar` (defaults to the official installer URL).
- `JD_SHA_PAGE_URL` – Support article URL that is scraped for the official JDownloader SHA256 checksum.
- `JD_SHA256` – Manual SHA256 override for `JDownloader.jar` when scraping the support article is undesired or fails.
- `SEVENZIP_BEST_URL` – SourceForge `best_release.json` endpoint to locate the latest sevenzipjbinding build.
- `SEVENZIP_FALLBACK_URL` – Static SourceForge URL used when the best-release lookup fails.
- `SEVENZIP_MD5` – Manual MD5 override for the sevenzipjbinding archive.
- `JDK_URL` – Direct override for the Temurin archive URL (skips GitHub tag lookup).
- `JDK_SHA256` – Manual SHA256 override for the JRE archive when checksum checks are enabled.
- `GITHUB_TOKEN` – Personal access token to avoid GitHub API rate limiting when resolving Temurin releases.

## Run example
```
docker run --name jDownloader2 -d \
    -p 8080:8080 \
    --env 'CUSTOM_RES_W=1024' \
    --env 'CUSTOM_RES_H=768' \
    --env 'UMASK=000' \
	--env 'UID=99' \
	--env 'GID=100' \
	--volume /mnt/user/appdata/jdownloader2:/jDownloader2 \
    --volume /mnt/user/jDownloader2:/mnt/jDownloader \
    --env 'JAVA_RUNTIME_VERSION=jdk-24.0.2+12' \
    --restart=unless-stopped\
	ich777/jdownloader2
```

### Webgui address: http://[SERVERIP]:[PORT]/vnc.html?autoconnect=true


#### Reverse Proxy with nginx example:

```
server {
	listen 443 ssl;

	include /config/nginx/ssl.conf;
	include /config/nginx/error.conf;

	server_name jdownloader2.example.com;

	location /websockify {
		auth_basic           example.com;
		auth_basic_user_file /config/nginx/.htpasswd;
		proxy_http_version 1.1;
		proxy_pass http://192.168.1.1:8080/;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "upgrade";

		# VNC connection timeout
		proxy_read_timeout 61s;

		# Disable cache
		proxy_buffering off;
	}
		location / {
		rewrite ^/$ https://jdownloader2.example.com/vnc.html?autoconnect=true redirect;
		auth_basic           example.com;
		auth_basic_user_file /config/nginx/.htpasswd;
		proxy_redirect     off;
		proxy_set_header Range $http_range;
		proxy_set_header If-Range $http_if_range;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "upgrade";
		proxy_pass http://192.168.1.1:8080/;
	}
}
```

## Set noVNC Password:
 Please be sure to create the password first inside the container, to do that open up a console from the container (Unraid: In the Docker tab click on the container icon and on 'Console' then type in the following):

1) **su $USER**
2) **vncpasswd**
3) **ENTER YOUR PASSWORD TWO TIMES AND PRESS ENTER AND SAY NO WHEN IT ASKS FOR VIEW ACCESS**

Unraid: close the console, edit the template and create a variable with the `Key`: `TURBOVNC_PARAMS` and leave the `Value` empty, click `Add` and `Apply`.

All other platforms running Docker: create a environment variable `TURBOVNC_PARAMS` that is empty or simply leave it empty:
```
    --env 'TURBOVNC_PARAMS='
```

This Docker was mainly edited for better use with Unraid, if you don't use Unraid you should definitely try it!

#### Support Thread: https://forums.unraid.net/topic/83786-support-ich777-application-dockers/
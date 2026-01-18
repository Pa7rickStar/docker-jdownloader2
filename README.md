# jDownloader2 in Docker optimized for Unraid

This Docker will download and install jDownloader2.

JDownloader 2 is a free, open-source download management tool with a huge community of developers that makes downloading as easy and fast as it should be. Users can start, stop or pause downloads, set bandwidth limitations, auto-extract archives and much more...

> [!TIP]
> Please also check out the homepage from jDownloader: <http://jdownloader.org/>

> [!NOTE]
> Updates will be handled through jDownloader2 directly, simply click the `Check for Updates` in the WebGUI.

## Flavors

This repository provides multiple Docker images (flavors) built from different Dockerfiles and published to GitHub Container Registry as `ghcr.io/<OWNER>/docker-jdownloader2:<flavor>`:

- `latest` – Alias for `legacy` for backward compatibility.
- `legacy` – Built from `Dockerfile`. Downloads jDownloader2, 7zip and Java from this repository.
- `download_official` – Built from `Dockerfile.download_official`. Downloads JDownloader2, 7zip and Java from the official sources and enforces checksum validation by default.
- `firefox` – Built from `Dockerfile.download_official` with `FLAVOR=firefox`. Same as `download_official`, but includes Firefox and an extended Fluxbox menu, so jDownloader's browser based captcha solving can be used.

> [!CAUTION]
> Changing flavours will overwrite/ remove some of your existing configuration files in the mounted volumes. Please back up your data before switching flavours! See [Changing flavors](#changing-flavors) for more information.

## Environment Variables and Build Arguments

### Basic params

| Name | Description | Default | Flavor |
| --- | --- | --- | --- |
| CUSTOM_RES_W | Width in pixels for the VNC window; values below 1024 are clamped to 1024. | 1280 | all |
| CUSTOM_RES_H | Height in pixels for the VNC window; values below 768 are clamped to 768. | 1024 | all |
| UMASK | Permissions for newly created files and folders | 000 | all |
| UID | User identifier used inside the container | 99 | all |
| GID | Group identifier used inside the container | 100 | all |
| SKIP_SHA_CHECKS | *(download_official / firefox only)* When `true` all checksum validation is skipped; when `false` (default) every JDownloader, sevenzip and JRE download must pass checksum validation or the build/startup aborts. | false | download_official, firefox |
| JAVA_RUNTIME_VERSION | *(download_official / firefox only)* Exact Temurin runtime tag to install. Changing this value will trigger a re-download of the matching JRE if the existing runtime version does not match. | jdk-24.0.2+12 | download_official, firefox |

### Advanced params

#### Build-time args (used when building the image yourself)

| Name | Description | Default | Flavor |
| --- | --- | --- | --- |
| JD_DOWNLOAD_URL | URL from which the image build downloads `JDownloader.jar`. | https://installer.jdownloader.org/JDownloader.jar | download_official, firefox |
| JD_SHA_PAGE_URL | Support article URL that is scraped for the official JDownloader SHA256 checksum. | https://support.jdownloader.org/de/knowledgebase/article/install-jdownloader-on-nas-and-embedded-devices | download_official, firefox |
| JD_SHA256 | Manual SHA256 override for `JDownloader.jar` when scraping the support article is undesired or fails. | empty (auto-scrape from support page) | download_official, firefox |
| SEVENZIP_BEST_URL | SourceForge `best_release.json` endpoint to locate the latest sevenzipjbinding build. | https://sourceforge.net/projects/sevenzipjbind/best_release.json | download_official, firefox |
| SEVENZIP_FALLBACK_URL | Static SourceForge URL used when the best-release lookup fails. | https://sourceforge.net/projects/sevenzipjbind/files/7-Zip-JBinding/16.02-2.01/sevenzipjbinding-16.02-2.01-Linux-amd64.zip/download?use_mirror=master | download_official, firefox |
| SEVENZIP_MD5 | Manual MD5 override for the sevenzipjbinding archive. | empty (taken from best_release.json when available) | download_official, firefox |
| FIREFOX_EXT_URL | URL of the Firefox extension XPI used for the browser captcha solver integration. | https://extensions.jdownloader.org/firefox.xpi | firefox |

#### Runtime env vars (mainly for the `download_official` / `firefox` flavors)

| Name | Description | Default | Flavor |
| --- | --- | --- | --- |
| CUSTOM_DEPTH | Color depth (bits per pixel) for the VNC session. Normally left at 16. | 16 | all |
| CONNECTED_CONTAINERS | Optional `host:port` of a VPN or proxy container to watch; if set, this container will restart itself when the connection is lost. | empty string | all |
| JDK_URL | Direct override for the Temurin archive URL (skips GitHub tag lookup). | unset | download_official, firefox |
| JDK_SHA256 | Manual SHA256 override for the JRE archive when checksum checks are enabled. | unset | download_official, firefox |
| DOWNLOAD_DIR | Default download folder path that jDownloader2 will use on first start for the official-download flavors. Point this to a path that is bind-mounted into the container. | /mnt/user/data/jdownloader | download_official, firefox |
| GITHUB_TOKEN | Personal access token to avoid GitHub API rate limiting when resolving Temurin releases. | empty string | download_official, firefox |

> [!NOTE]
> For the `legacy` flavor, the download directory in the container is hardcoded to `/mnt/jDownloader` and cannot be changed via env vars.

## Run example

```bash
docker run --name jDownloader2 -d \
    -p 8080:8080 \
    --env 'CUSTOM_RES_W=1024' \
    --env 'CUSTOM_RES_H=768' \
    --env 'UMASK=000' \
    --env 'UID=99' \
    --env 'GID=100' \
    --env 'SKIP_SHA_CHECKS=false' \
    --env 'JAVA_RUNTIME_VERSION=jdk-24.0.2+12' \
    --env 'GITHUB_TOKEN=""' \
    --volume /mnt/user/appdata/jdownloader2:/jDownloader2 \
    --volume /mnt/user/jDownloader2:/mnt/jDownloader \
    --restart=unless-stopped \
    ghcr.io/<OWNER>/docker-jdownloader2:download_official
```

Replace `<OWNER>` with the GitHub user or organization that owns this repository. To run another flavor, replace `:download_official` with `:legacy`, `:latest` or `:firefox`.

### Webgui address

`http://[SERVERIP]:[PORT]/vnc.html?autoconnect=true`

#### Reverse Proxy with nginx example

```plaintext
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

## Set noVNC Password

 Please be sure to create the password first inside the container, to do that open up a console from the container (Unraid: In the Docker tab click on the container icon and on 'Console' then type in the following):

```bash
su $USER
vncpasswd
```

Enter your password two times and press enter and say no when it asks for view access.

### Unraid

close the console, edit the template and create a variable with the `Key`: `TURBOVNC_PARAMS` and leave the `Value` empty, click `Add` and `Apply`.

### All other platforms running Docker

Create a environment variable `TURBOVNC_PARAMS` that is empty or simply leave it empty:

```dockerfile
    --env 'TURBOVNC_PARAMS='
```

This Docker was mainly edited for better use with Unraid, if you don't use Unraid you should definitely try it!

## Changing flavors

Flavours can be changed by changing the image tag in the docker run command, compose file or Unraid template.

When switching flavors the container adjusts a few configuration files inside the data volume (`/jDownloader2`):

- Fluxbox configuration under `/etc/.fluxbox` is flavor-specific; on **each start** a snapshot of the current state is backed up.
- When starting the `legacy` flavor, any non-default runtime directories under `/jDownloader2/runtime` are moved to `/jDownloader2/backups/runtime/` to avoid conflicts with the legacy Java runtime.

Backups are not restored automatically. They are written into the mounted data path so they can be restored manually if needed:

- `/jDownloader2/backups/etc/.fluxbox/`
- `/jDownloader2/backups/runtime/`

> [!NOTE]
> When bind-mounting `/etc/.fluxbox` from the host, the host directory controls Fluxbox for all flavors and the per-flavor defaults from the image (including the extended Firefox menu) will not be applied automatically.

## Support Thread

<https://forums.unraid.net/topic/83786-support-ich777-application-dockers/>

#!/usr/bin/env python3
import os, sys, re, json, hashlib, tarfile, zipfile, io, shutil
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path

# -------- helpers --------
def log(msg):  # to stderr (won't be eval'ed by the shell)
    print(f"---{msg}", file=sys.stderr, flush=True)

def getenv(name, default=""):
    return os.environ.get(name, default)

def http_get(url, token=None, accept="application/vnd.github+json", binary=False, retries=3):
    headers = {"User-Agent": "fetch-temurin/1.0"}
    if accept:
        headers["Accept"] = accept
    if token:
        headers["Authorization"] = f"token {token}"
    last_err = None
    for _ in range(retries):
        try:
            req = Request(url, headers=headers)
            with urlopen(req, timeout=60) as r:
                data = r.read()
                return data if binary else data.decode("utf-8", "replace")
        except (HTTPError, URLError) as e:
            last_err = e
    raise last_err

def parse_installed_jre(runtime_root: Path):
    """Return (installed_version, runtime_subpath) or ('','')"""
    if not runtime_root.is_dir():
        return "", ""
    for rel in runtime_root.rglob("release"):
        try:
            text = rel.read_text("utf-8", errors="ignore")
            m = re.search(r'^\s*JAVA_RUNTIME_VERSION=["\']?([\w.+-]+)', text, re.M)
            if m:
                ver = m.group(1)
                subpath = str(rel.relative_to(runtime_root).parent).replace("\\", "/")
                return ver, subpath
        except Exception:
            continue
    return "", ""

def decide_target(req: str, installed_major: str | None):
    """Return (repo, use_latest, tag, major) for Adoptium."""
    def major_from(ver: str) -> str:
        # take digits before '+', '.', or '-'
        return re.split(r'[+.\-]', ver)[0]
    req = (req or "").strip()
    if req == "" or req.lower() == "latest":
        major = installed_major or os.environ.get("DEFAULT_TEMURIN_MAJOR", "21")
        return f"adoptium/temurin{major}-binaries", True, "", major
    if req.startswith("jdk-"):
        ver = req[4:]
        major = major_from(ver)
        return f"adoptium/temurin{major}-binaries", False, req, major
    if re.match(r'^\d+', req):
        major = major_from(req)
        if re.fullmatch(r'\d+', req):
            return f"adoptium/temurin{major}-binaries", True, "", major
        else:
            return f"adoptium/temurin{major}-binaries", False, f"jdk-{req}", major
    # fallback
    major = installed_major or "21"
    return f"adoptium/temurin{major}-binaries", True, "", major

def pick_asset(release_json: dict):
    """Prefer linux x64 JRE, then JDK; avoid alpine/debug/static/symbols; tar/zip."""
    assets = release_json.get("assets") or []
    def ok(a, kind):
        n = (a.get("name") or "").lower()
        if "linux" not in n: return False
        if "alpine" in n: return False
        if not ("x64" in n or "x86_64" in n): return False
        if kind not in n: return False
        if not (n.endswith(".tar.gz") or n.endswith(".tgz") or n.endswith(".tar") or n.endswith(".zip")):
            return False
        for bad in ("debugimage","testimage","static","symbols"):
            if bad in n: return False
        return True
    for kind in ("jre", "jdk"):
        for a in assets:
            if ok(a, kind):
                return a["name"], a["browser_download_url"]
    return "", ""

def find_sha_asset_for(assets: list, asset_basename: str):
    # exact match "<asset>.sha256.txt"
    for a in assets:
        if a.get("name") == f"{asset_basename}.sha256.txt":
            return a.get("browser_download_url")
    # otherwise any sha256 list
    for a in assets:
        n = (a.get("name") or "").lower()
        if n.endswith("sha256.txt") or "sha256" in n:
            return a.get("browser_download_url")
    return ""

def sha256_bytes(b: bytes) -> str:
    h = hashlib.sha256()
    h.update(b)
    return h.hexdigest()

def safe_extract_tar(tarf: tarfile.TarFile, dest: Path):
    dest = dest.resolve()
    for m in tarf.getmembers():
        p = dest.joinpath(m.name)
        if not str(p.resolve()).startswith(str(dest) + os.sep):
            raise RuntimeError("Unsafe path in tar archive")
    tarf.extractall(dest)

def safe_extract_zip(zf: zipfile.ZipFile, dest: Path):
    dest = dest.resolve()
    for n in zf.namelist():
        p = dest.joinpath(n)
        if not str(p.resolve()).startswith(str(dest) + os.sep):
            raise RuntimeError("Unsafe path in zip archive")
    zf.extractall(dest)

# -------- main --------
def main():
    data_dir = Path(getenv("DATA_DIR", "/jDownloader2"))
    runtime_root = data_dir / "runtime"
    token = getenv("GITHUB_TOKEN", "") or None
    req = getenv("JRE_VERSION", "latest").strip()
    force_sha = getenv("FORCE_SHA_CHECK", "").lower() in ("1","true","yes")
    # discover existing runtime
    installed_ver, runtime_name = parse_installed_jre(runtime_root)
    print_vars = {}  # will print as shell assignments at the end
    print_vars["INSTALLED_JRE"] = installed_ver or ""
    log(f"Checking if Runtime is installed---")
    log(f"INSTALLED_JRE={installed_ver or '<none>'} RUNTIME_NAME={runtime_name or '<none>'}---")

    installed_major = installed_ver.split(".", 1)[0] if installed_ver else None
    repo, use_latest, tag, major = decide_target(req, installed_major)
    log(f"JRE_VERSION requested: {req or 'latest'} (installed: {installed_ver or '<none>'}); repo={repo}---")

    # If use_latest and installed major matches -> keep current
    if use_latest and installed_major and installed_major == major:
        log(f"Installed major {installed_major} already satisfies requested {req or 'latest'} ---")
        print_vars["RUNTIME_NAME"] = runtime_name or ""
        # print and exit 0
        for k,v in print_vars.items():
            print(f"{k}={sh_quote(v)}")
        return 0

    # fetch release JSON
    try:
        if use_latest:
            url = f"https://api.github.com/repos/{repo}/releases/latest"
        else:
            url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
        log(f"Fetching release metadata: {url}")
        rel_text = http_get(url, token=token)
        rel = json.loads(rel_text)
    except Exception as e:
        log(f"ERROR: cannot fetch release metadata from {repo}: {e}")
        return 1

    # pick asset
    name, url = pick_asset(rel)
    if not url:
        log("ERROR: no suitable linux x64 JRE/JDK asset found in release metadata---")
        return 1
    log(f"Selected asset: {name}---")
    asset_base = Path(name).name

    # download asset
    tmp_dir = Path("/tmp")
    tmp_dir.mkdir(parents=True, exist_ok=True)
    asset_path = tmp_dir / asset_base
    try:
        log(f"Downloading asset...")
        data = http_get(url, token=token, accept=None, binary=True)
    except Exception as e:
        log(f"ERROR: download failed: {e}")
        return 1

    # detect HTML error
    head = data[:256].lower()
    if b"<html" in head:
        log("ERROR: Downloaded file looks like HTML (probably an error page)—printing first lines:")
        try:
            log(data.decode("utf-8", "replace").splitlines()[0][:200])
        except Exception:
            pass
        return 1

    # write file and compute sha
    asset_path.write_bytes(data)
    actual_sha = sha256_bytes(data)

    # checksum
    check_url = find_sha_asset_for(rel.get("assets") or [], asset_base)
    if check_url:
        try:
            sha_txt = http_get(check_url, token=token, accept=None, binary=False)
            exp_sha = ""
            for line in sha_txt.splitlines():
                # format: HEX [*]FILENAME  (sometimes with path)
                m = re.match(r'^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$', line)
                if m:
                    hex_, fn = m.group(1).lower(), m.group(2).strip()
                    if fn.endswith(asset_base):
                        exp_sha = hex_
                        break
            log(f"Checksum (expected): {exp_sha or '<none>'}---")
            log(f"Checksum (actual)  : {actual_sha}---")
            if exp_sha and exp_sha != actual_sha:
                msg = "ERROR: checksum mismatch for downloaded asset"
                if force_sha:
                    log(msg)
                    return 1
                else:
                    log(msg + " (continuing because FORCE_SHA_CHECK is not set)---")
        except Exception as e:
            if force_sha:
                log(f"ERROR: failed to download/parse checksum asset and FORCE_SHA_CHECK is enabled: {e}")
                return 1
            else:
                log(f"WARNING: failed to download/parse checksum asset: {e} (continuing)---")
    else:
        if force_sha:
            log("ERROR: no checksum asset found and FORCE_SHA_CHECK is enabled")
            return 1
        else:
            log("No checksum asset found; continuing without verification---")

    # peek top-level dir
    topdir = ""
    try:
        if asset_base.endswith(".zip"):
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                first = (zf.namelist() or [""])[0]
                topdir = (first.split("/",1)[0] if "/" in first else first)
        else:
            # tar, tgz, tar.gz
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
                m = tf.next()
                if m:
                    name0 = m.name
                    topdir = (name0.split("/",1)[0] if "/" in name0 else name0)
    except Exception as e:
        log(f"WARNING: could not inspect archive top-level: {e}")

    if topdir:
        log(f"Archive top-level dir: {topdir}---")

    # extract safely to runtime/
    runtime_root.mkdir(parents=True, exist_ok=True)
    try:
        if asset_base.endswith(".zip"):
            with zipfile.ZipFile(asset_path) as zf:
                safe_extract_zip(zf, runtime_root)
        else:
            with tarfile.open(asset_path, mode="r:*") as tf:
                safe_extract_tar(tf, runtime_root)
    except Exception as e:
        log(f"ERROR: extraction failed: {e}")
        return 1

    # determine installed runtime subpath
    if topdir and (runtime_root / topdir).is_dir():
        runtime_name2 = topdir
    else:
        ver2, sub2 = parse_installed_jre(runtime_root)
        runtime_name2 = sub2

    if not runtime_name2:
        log("ERROR: could not determine extracted runtime directory")
        return 1

    # optionally chown to UID/GID if provided
    try:
        uid = int(os.environ.get("UID",""))
        gid = int(os.environ.get("GID",""))
        for p in (runtime_root / runtime_name2).rglob("*"):
            try:
                os.chown(str(p), uid, gid)
            except Exception:
                pass
        try:
            os.chown(str(runtime_root / runtime_name2), uid, gid)
        except Exception:
            pass
    except Exception:
        pass

    print_vars["RUNTIME_NAME"] = runtime_name2

    # finally: print only assignments for the shell to eval
    for k, v in print_vars.items():
        print(f"{k}={sh_quote(v)}")
    return 0

def sh_quote(s: str) -> str:
    # POSIX-safe single-quote
    if s is None:
        s = ""
    return "'" + s.replace("'", "'\"'\"'") + "'"

if __name__ == "__main__":
    rc = main()
    sys.exit(rc)

#!/usr/bin/env python3
"""
Deploy compiled release artifacts to Theaver API and MinIO storage,
and register them in the PostgreSQL database.
Can be executed in GitHub Actions or locally.
"""

import argparse
import http.client
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

CHUNK_SIZE = 256 * 1024  # 256 KB chunks
CHUNK_TIMEOUT_SEC = 12  # Per-chunk socket write timeout
RESPONSE_TIMEOUT_SEC = 600  # Timeout waiting for final server response after upload completes
MIN_SPEED_BYTES_PER_SEC = 512 * 1024  # 512 KB/s minimum speed after warmup
SPEED_WARMUP_SEC = 4.0  # Check speed after 4 seconds
MAX_RETRIES = 12

# Persistent HTTP/1.1 Keep-Alive connection and quarantined slow sockets
# (kept open until script exit so Azure SNAT cannot reassign throttled source ports)
_active_conn = None
_active_host_port = None
_quarantined_conns = []


class ThrottledConnectionError(Exception):
    pass


def _get_or_create_conn(url):
    global _active_conn, _active_host_port
    parsed = urllib.parse.urlsplit(url)
    is_https = parsed.scheme.lower() == "https"
    host = parsed.hostname
    port = parsed.port or (443 if is_https else 80)
    key = (is_https, host, port)

    if _active_conn is not None and _active_host_port == key and getattr(_active_conn, "sock", None) is not None:
        return _active_conn, parsed, True

    if is_https:
        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(host, port, timeout=CHUNK_TIMEOUT_SEC, context=ctx)
    else:
        conn = http.client.HTTPConnection(host, port, timeout=CHUNK_TIMEOUT_SEC)

    conn.connect()
    if conn.sock is not None:
        try:
            conn.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            conn.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 256 * 1024)
        except Exception:
            pass
        conn.sock.settimeout(CHUNK_TIMEOUT_SEC)

    _active_conn = conn
    _active_host_port = key
    return conn, parsed, False


def _quarantine_active_conn():
    """Keep slow socket open in quarantine list so SNAT allocates a fresh source port on next connect."""
    global _active_conn
    if _active_conn is not None:
        _quarantined_conns.append(_active_conn)
        _active_conn = None


def _discard_active_conn():
    global _active_conn
    if _active_conn is not None:
        try:
            _active_conn.close()
        except Exception:
            pass
        _active_conn = None


def _cleanup_all_conns():
    _discard_active_conn()
    while _quarantined_conns:
        c = _quarantined_conns.pop()
        try:
            c.close()
        except Exception:
            pass


def _stream_multipart_once(url, file_path, fields, headers, chunk_size=CHUNK_SIZE):
    conn, parsed, reused = _get_or_create_conn(url)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    file_size = os.path.getsize(file_path)
    file_name = os.path.basename(file_path)
    boundary = f"----WebKitFormBoundary{uuid.uuid4().hex}"

    # Ensure file_size is sent as a form field BEFORE the file stream
    all_fields = dict(fields)
    all_fields["file_size"] = str(file_size)

    prefix = bytearray()
    for name, value in all_fields.items():
        prefix.extend(f"--{boundary}\r\n".encode("utf-8"))
        prefix.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        prefix.extend(f"{value}\r\n".encode("utf-8"))

    prefix.extend(f"--{boundary}\r\n".encode("utf-8"))
    prefix.extend(
        f'Content-Disposition: form-data; name="file"; filename="{file_name}"\r\n'.encode("utf-8")
    )
    prefix.extend(b"Content-Type: application/octet-stream\r\n\r\n")

    suffix = f"\r\n--{boundary}--\r\n".encode("utf-8")
    total_length = len(prefix) + file_size + len(suffix)

    req_headers = dict(headers)
    req_headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    req_headers["Content-Length"] = str(total_length)
    req_headers["Connection"] = "keep-alive"
    req_headers["X-File-Size"] = str(file_size)
    if "channel" in all_fields:
        req_headers["X-Channel"] = str(all_fields["channel"])

    local_port = None
    try:
        if conn.sock is not None:
            local_port = conn.sock.getsockname()[1]
    except Exception:
        pass

    if reused:
        print(f"  ↳ Reusing fast Keep-Alive socket (local port {local_port})", flush=True)
    else:
        print(f"  ↳ Opened new socket (local port {local_port}, quarantined={len(_quarantined_conns)})", flush=True)

    if conn.sock is not None:
        conn.sock.settimeout(CHUNK_TIMEOUT_SEC)

    conn.putrequest("POST", path)
    for k, v in req_headers.items():
        conn.putheader(k, v)
    conn.endheaders()

    # 1. Send multipart headers prefix
    conn.send(bytes(prefix))

    # 2. Stream file in 256 KB blocks with per-chunk timeout and minimum speed guard
    sent_bytes = 0
    next_milestone = 25
    start_ts = time.monotonic()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            if conn.sock is not None:
                conn.sock.settimeout(CHUNK_TIMEOUT_SEC)
            conn.send(chunk)
            sent_bytes += len(chunk)

            elapsed = max(0.05, time.monotonic() - start_ts)
            avg_speed = sent_bytes / elapsed

            # Detect DPI/ECMP throttled route (< 512 KB/s after warmup) and quarantine socket immediately
            if elapsed >= SPEED_WARMUP_SEC and avg_speed < MIN_SPEED_BYTES_PER_SEC:
                raise ThrottledConnectionError(
                    f"Throttled route detected ({avg_speed / 1024:.1f} KB/s after {elapsed:.1f}s on port {local_port})"
                )

            if file_size > 0:
                pct = int((sent_bytes * 100) / file_size)
                if pct >= next_milestone and next_milestone <= 100:
                    speed_mb = (sent_bytes / (1024 * 1024)) / elapsed
                    print(
                        f"  ↳ {file_name}: {pct}% ({sent_bytes // (1024 * 1024)}/{file_size // (1024 * 1024)} MB, {speed_mb:.2f} MB/s)",
                        flush=True,
                    )
                    while next_milestone <= pct:
                        next_milestone += 25

    # 3. Send closing boundary suffix
    conn.send(suffix)

    # 4. Wait for server response (MinIO finalize / web tar extraction)
    if conn.sock is not None:
        conn.sock.settimeout(RESPONSE_TIMEOUT_SEC)

    resp = conn.getresponse()
    raw_body = resp.read().decode("utf-8", errors="replace")
    status = resp.status
    if resp.will_close:
        _discard_active_conn()

    try:
        parsed_json = json.loads(raw_body)
    except Exception:
        parsed_json = {"error": f"HTTP {status}: {raw_body}"}
    return parsed_json, status


def post_multipart(url, file_path, fields, headers, max_retries=MAX_RETRIES):
    file_name = os.path.basename(file_path)
    last_res = {"error": "Unknown upload error"}
    last_status = 500

    for attempt in range(1, max_retries + 1):
        try:
            res, status = _stream_multipart_once(url, file_path, fields, headers)
            if status == 200 and res.get("success"):
                return res, status

            _discard_active_conn()
            last_res, last_status = res, status
            print(
                f"[Deploy] ⚠️ Attempt {attempt}/{max_retries} for {file_name} returned HTTP {status}: {res}",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(2)
        except (ThrottledConnectionError, TimeoutError, socket.timeout) as e:
            # Quarantine slow/timed-out socket so SNAT allocates a fresh source port immediately
            _quarantine_active_conn()
            last_res = {"error": str(e)}
            last_status = 500
            print(
                f"[Deploy] ⚡ Attempt {attempt}/{max_retries} for {file_name}: {e} -> switching SNAT port...",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(0.5)
        except Exception as e:
            _discard_active_conn()
            last_res = {"error": str(e)}
            last_status = 500
            print(
                f"[Deploy] ⚠️ Attempt {attempt}/{max_retries} for {file_name} failed with exception: {e}",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(1.5)

    return last_res, last_status


def post_json(url, payload, headers, max_retries=MAX_RETRIES):
    body = json.dumps(payload).encode("utf-8")
    req_headers = dict(headers)
    req_headers["Content-Type"] = "application/json"
    req_headers["Content-Length"] = str(len(body))
    req_headers["Connection"] = "keep-alive"

    last_res = {"error": "Unknown error"}
    last_status = 500

    for attempt in range(1, max_retries + 1):
        try:
            conn, parsed, _ = _get_or_create_conn(url)
            path = parsed.path or "/"
            if parsed.query:
                path = f"{path}?{parsed.query}"
            if conn.sock is not None:
                conn.sock.settimeout(30)
            conn.putrequest("POST", path)
            for k, v in req_headers.items():
                conn.putheader(k, v)
            conn.endheaders()
            conn.send(body)
            resp = conn.getresponse()
            raw_body = resp.read().decode("utf-8", errors="replace")
            status = resp.status
            if resp.will_close:
                _discard_active_conn()
            return json.loads(raw_body), status
        except Exception as e:
            _quarantine_active_conn()
            last_res, last_status = {"error": str(e)}, 500
            time.sleep(0.5)

    return last_res, last_status



def main():
    parser = argparse.ArgumentParser(description="Upload and register releases in Theaver API.")
    parser.add_argument("--artifacts-dir", required=True, help="Directory containing release files.")
    parser.add_argument("--api-url", default=None, help="Theaver API base URL.")
    parser.add_argument("--admin-secret", default=None, help="Theaver admin secret key.")
    parser.add_argument("--version", required=True, help="Release version (e.g. 1.0.1).")
    parser.add_argument("--build-number", type=int, required=True, help="Release build number.")
    parser.add_argument("--channel", default="stable", choices=["stable", "beta", "alpha"], help="Release channel.")
    parser.add_argument("--release-notes-file", default=None, help="Path to changelog / release notes file.")
    parser.add_argument("--force-update", action="store_true", help="Mark release as mandatory force update.")
    parser.add_argument("--strict", action="store_true", help="Fail if secrets are missing.")

    args = parser.parse_args()

    api_url = (args.api_url or os.environ.get("THEAVER_API_URL") or "https://api.theaver.app").rstrip("/")
    admin_secret = args.admin_secret or os.environ.get("THEAVER_ADMIN_SECRET") or ""

    if not admin_secret:
        msg = "[Deploy] WARNING: THEAVER_ADMIN_SECRET is not configured. Skipping deployment to Theaver API."
        if args.strict:
            print(msg, file=sys.stderr, flush=True)
            sys.exit(1)
        else:
            print(msg, flush=True)
            sys.exit(0)

    release_notes = ""
    if args.release_notes_file and os.path.exists(args.release_notes_file):
        try:
            with open(args.release_notes_file, "r", encoding="utf-8") as f:
                release_notes = f.read().strip()
        except Exception as e:
            print(f"[Deploy] Warning: could not read release notes: {e}", flush=True)

    if not os.path.isdir(args.artifacts_dir):
        print(f"[Deploy] Error: artifacts directory not found: {args.artifacts_dir}", file=sys.stderr, flush=True)
        sys.exit(1)

    # Collect distribution files
    valid_exts = (".apk", ".ipa", ".zip", ".tar.gz", ".exe", ".msix", ".dmg", ".deb", ".rpm", ".appimage")
    files_to_deploy = []
    for root, _, files in os.walk(args.artifacts_dir):
        for f in files:
            lower = f.lower()
            if any(lower.endswith(ext) for ext in valid_exts):
                files_to_deploy.append(os.path.join(root, f))

    if not files_to_deploy:
        print(f"[Deploy] No release files found in {args.artifacts_dir}", flush=True)
        sys.exit(0)

    print(f"[Deploy] Found {len(files_to_deploy)} file(s) to upload & deploy to {api_url}:", flush=True)
    for f in files_to_deploy:
        print(f"  • {os.path.basename(f)}", flush=True)

    headers = {
        "X-Admin-Secret": admin_secret,
        "User-Agent": "Theaver-Release-Deployer/2.0"
    }

    success_count = 0
    fail_count = 0

    # Deploy web bundle first (smallest and updates live web frontend immediately), then sort remaining files
    ordered_files = sorted(
        files_to_deploy,
        key=lambda p: (0 if "-web." in os.path.basename(p).lower() else 1, os.path.basename(p).lower()),
    )

    try:
        for file_path in ordered_files:
            fname = os.path.basename(file_path)
            fsize = os.path.getsize(file_path)
            print(f"\n[Deploy] Processing {fname} ({fsize} bytes)...", flush=True)

            # 1. Stream release binary to MinIO via API in 256 KB chunks
            upload_endpoint = f"{api_url}/api/admin/upload-release"
            fields = {"channel": args.channel}

            upload_res, status = post_multipart(upload_endpoint, file_path, fields, headers)
            if status != 200 or not upload_res.get("success"):
                print(f"[Deploy] ❌ Failed to upload {fname}: {upload_res}", file=sys.stderr, flush=True)
                fail_count += 1
                continue

            download_url = upload_res.get("download_url")
            platform = upload_res.get("platform") or upload_res.get("detected_platform") or "android"
            arch = upload_res.get("architecture") or upload_res.get("detected_architecture") or "universal"
            sha256 = upload_res.get("sha256") or ""
            size_bytes = upload_res.get("size_bytes") or upload_res.get("file_size_bytes") or fsize

            print(f"[Deploy] ✅ Uploaded successfully: {download_url}", flush=True)
            print(f"[Deploy] Metadata: Platform={platform}, Arch={arch}, Channel={args.channel}, Size={size_bytes}", flush=True)

            # 2. Register release in DB
            version_endpoint = f"{api_url}/api/admin/version"
            version_payload = {
                "platform": platform,
                "architecture": arch,
                "channel": args.channel,
                "latest_version": args.version,
                "latest_build": args.build_number,
                "min_supported_build": 1,
                "force_update": args.force_update,
                "download_url": download_url,
                "apk_size_bytes": size_bytes,
                "sha256": sha256,
                "release_notes": release_notes
            }

            ver_res, ver_status = post_json(version_endpoint, version_payload, headers)
            if ver_status != 200 or not ver_res.get("success"):
                print(f"[Deploy] ❌ Failed to register {platform}/{arch}/{args.channel} in database: {ver_res}", file=sys.stderr, flush=True)
                fail_count += 1
                continue

            print(f"[Deploy] ✅ Registered in database successfully!", flush=True)
            success_count += 1
    finally:
        _cleanup_all_conns()

    print(f"\n[Deploy] Deployment finished. Successful: {success_count}, Failed: {fail_count}", flush=True)
    if fail_count > 0 and args.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()



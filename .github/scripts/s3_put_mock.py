#!/usr/bin/env python3
"""upload-sample.* を試すための、PUT だけを受け取る小さな HTTP サーバー.

CI 用. AWS にも S3 エミュレータにもつながない.

PUT /<バケット>/<キー> の本文を <保存先>/<バケット>/<キー> に書き、200 を返す. それ以外のメソッドは 405.
バケットは --bucket で決めたものだけを受け付ける（別のバケット名に送ったら 404）.
スクリプトが .env の S3_BUCKET を読めているかを確かめるため.

使い方: python .github/scripts/s3_put_mock.py --port 19090 --bucket ci-bucket --out <保存先> [--ready-file <path>]
  --ready-file: 待ち受けを始めたら、このファイルを作る（起動を待つ側が使う）
"""

from __future__ import annotations

import argparse
import contextlib
import socket
import sys
import threading
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Handler(BaseHTTPRequestHandler):
    def __init__(self, *args, bucket: str, out: Path, **kwargs):
        self.bucket = bucket
        self.out = out
        super().__init__(*args, **kwargs)

    def do_PUT(self) -> None:  # noqa: N802 (http.server の決まった名前)
        parts = [unquote(p) for p in urlsplit(self.path).path.split("/") if p]
        if len(parts) < 2 or any(p in (".", "..") for p in parts):
            self.reply(400, "bad path")
            return
        if parts[0] != self.bucket:
            self.reply(404, f"NoSuchBucket: {parts[0]}")
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        dest = self.out.joinpath(*parts)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(body)
        self.reply(200, "")

    def do_GET(self) -> None:  # noqa: N802
        self.reply(405, "PUT only")

    def reply(self, status: int, text: str) -> None:
        data = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class V6Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6


def make_servers(port: int, bucket: str, out: Path) -> list[ThreadingHTTPServer]:
    """この PC の中（127.0.0.1 と ::1）だけで待ち受ける.

    localhost が ::1 と 127.0.0.1 のどちらに解決されても受け付ける（Windows は ::1 を先に試す）.
    port に 0 を渡すと空いているポートを選び、::1 も同じポートにする.
    """
    handler = partial(Handler, bucket=bucket, out=out)
    servers: list[ThreadingHTTPServer] = [ThreadingHTTPServer(("127.0.0.1", port), handler)]
    with contextlib.suppress(OSError):  # IPv6 が無い環境では 127.0.0.1 だけ
        servers.append(V6Server(("::1", servers[0].server_address[1]), handler))
    return servers


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--ready-file", type=Path)
    args = ap.parse_args(argv)
    servers = make_servers(args.port, args.bucket, args.out)
    for extra in servers[1:]:
        threading.Thread(target=extra.serve_forever, daemon=True).start()
    if args.ready_file:
        args.ready_file.write_text("ready", encoding="utf-8")
    print(f"listening on port {args.port} (bucket {args.bucket})", flush=True)
    with contextlib.suppress(KeyboardInterrupt):
        servers[0].serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())

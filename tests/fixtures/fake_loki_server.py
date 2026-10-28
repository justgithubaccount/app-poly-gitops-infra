#!/usr/bin/env python3
"""Minimal Loki query_range fixture for trace-correlated log verification."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class Handler(BaseHTTPRequestHandler):
    trace_id = ""
    service_name = ""

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        request = urlparse(self.path)
        if request.path != "/loki/api/v1/query_range":
            self.send_error(404)
            return
        if self.trace_id not in parse_qs(request.query).get("query", [""])[0]:
            self.send_error(400)
            return
        line = json.dumps(
            {
                "message": "project chat completed",
                "service.name": self.service_name,
                "trace_id": self.trace_id,
            }
        )
        body = json.dumps(
            {
                "status": "success",
                "data": {
                    "resultType": "streams",
                    "result": [
                        {
                            "stream": {"stream": "otel"},
                            "values": [["1", line]],
                        }
                    ],
                },
            }
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--trace-id", required=True)
    parser.add_argument("--service-name", required=True)
    args = parser.parse_args()

    Handler.trace_id = args.trace_id
    Handler.service_name = args.service_name
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(args.port_file).write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()

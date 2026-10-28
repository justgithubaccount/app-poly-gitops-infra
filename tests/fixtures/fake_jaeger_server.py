#!/usr/bin/env python3
"""Minimal Jaeger API v3 fixture for trace verification."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    trace_id = ""
    service_name = ""

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        if self.path != f"/api/v3/traces/{self.trace_id}":
            self.send_error(404)
            return
        body = json.dumps(
            {
                "result": {
                    "resourceSpans": [
                        {
                            "resource": {
                                "attributes": [
                                    {
                                        "key": "service.name",
                                        "value": {"stringValue": self.service_name},
                                    }
                                ]
                            }
                        }
                    ]
                }
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

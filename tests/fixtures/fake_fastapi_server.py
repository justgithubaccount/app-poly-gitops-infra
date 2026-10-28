#!/usr/bin/env python3
"""Minimal HTTP fixture for the FastAPI runtime smoke client."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    project_id = "runtime-smoke-project"
    project_name = ""
    history: list[dict[str, str]] = []
    chat_error = False
    trace_id = "00000000000000000000000000000001"

    def log_message(self, format: str, *args: object) -> None:
        return

    def send_json(self, status: int, payload: object) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def do_GET(self) -> None:
        if self.path == "/":
            self.send_json(200, {"status": "ok", "service": "Chat Microservice", "version": "test"})
        elif self.path == "/health":
            self.send_json(200, {"status": "ok"})
        elif self.path == "/api/v1/projects":
            projects = []
            if self.project_name:
                projects.append({"id": self.project_id, "name": self.project_name})
            self.send_json(200, projects)
        elif self.path == f"/api/v1/projects/{self.project_id}/history":
            self.send_json(200, self.history)
        else:
            self.send_json(404, {"detail": "not found"})

    def do_POST(self) -> None:
        payload = self.read_json()
        if self.path == "/api/v1/projects":
            type(self).project_name = payload["name"]
            self.send_json(200, {"id": self.project_id, "name": self.project_name})
        elif self.path == "/api/v1/chat":
            if not payload.get("messages"):
                self.send_json(422, {"detail": "messages must not be empty"})
                return
            reply = "Ошибка API: invalid key" if self.chat_error else "FASTAPI_SMOKE_OK"
            self.send_json(200, {"reply": reply})
        elif self.path == f"/api/v1/projects/{self.project_id}/chat":
            type(self).history = [
                {
                    "id": "history-1",
                    "project_id": self.project_id,
                    "messages": payload["messages"],
                    "trace_id": self.trace_id,
                    "span_id": None,
                    "timestamp": "2026-10-28T00:00:00Z",
                }
            ]
            self.send_json(200, {"reply": "PROJECT_SMOKE_OK"})
        else:
            self.send_json(404, {"detail": "not found"})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--chat-error", action="store_true")
    args = parser.parse_args()

    Handler.chat_error = args.chat_error
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(args.port_file).write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()

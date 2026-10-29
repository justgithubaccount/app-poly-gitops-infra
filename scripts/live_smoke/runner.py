"""Real service/browser/model verification on a disposable Actions runner."""

import argparse
import gzip
import json
import os
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from budget import BudgetGate, GateError, openai_upstream
from opentelemetry.proto.collector.trace.v1.trace_service_pb2 import (
    ExportTraceServiceRequest,
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    sources = args.sources.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        raise SystemExit("OPENAI_API_KEY repository secret is required")

    gate = BudgetGate(openai_upstream(key))
    spans = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            if length > 2_000_000:
                self.send_error(413)
                return
            raw = self.rfile.read(length)
            if self.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            if self.path == "/v1/traces":
                export = ExportTraceServiceRequest.FromString(raw)
                for resource in export.resource_spans:
                    service = next(
                        (
                            a.value.string_value
                            for a in resource.resource.attributes
                            if a.key == "service.name"
                        ),
                        "unknown",
                    )
                    for scope in resource.scope_spans:
                        for span in scope.spans:
                            spans.append(
                                {
                                    "service": service,
                                    "name": span.name,
                                    "trace_id": span.trace_id.hex(),
                                }
                            )
                self.send_response(200)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path not in ("/v1/chat/completions", "/chat/completions"):
                self.send_error(404)
                return
            try:
                status, result = gate.complete(json.loads(raw))
            except GateError as error:
                status, result = error.status, {"error": {"message": str(error)}}
            except (ValueError, TypeError):
                status, result = 400, {"error": {"message": "Invalid smoke request"}}
            payload = json.dumps(result).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 8133), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    children = []
    summary = {
        "result": "FAIL",
        "cloud_resources_created": False,
        "cluster_tools_executed": False,
        "model_provider": "real OpenAI",
    }

    # Never inherit the real key or unrelated runner credentials into children.
    env = {
        name: value
        for name, value in os.environ.items()
        if not any(
            word in name.upper() for word in ("KEY", "TOKEN", "SECRET", "PASSWORD")
        )
    }
    env.update(
        {
            "OPENAI_API_KEY": "runner-local-smoke",
            "OPENROUTER_API_KEY": "runner-local-smoke",
            "OPENAI_BASE_URL": "http://127.0.0.1:8133/v1",
            "OPENAI_API_BASE": "http://127.0.0.1:8133/v1",
            "OPENROUTER_API_URL": "http://127.0.0.1:8133/chat/completions",
            "OPENROUTER_MODEL": "gpt-4o-mini",
            "ALLOW_MUTATING": "false",
            "GITHUB_TOKEN": "",
            "CLOUDFLARE_API_TOKEN": "",
            "ARGOCD_API_TOKEN": "",
            "CREWAI_DISABLE_TELEMETRY": "true",
            "CREWAI_DISABLE_TRACKING": "true",
            "OTEL_SDK_DISABLED": "false",
            "OTEL_TRACES_EXPORTER": "otlp",
            "OTEL_LOGS_EXPORTER": "none",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:8133",
            "ENVIRONMENT": "test",
            "APP_VERSION": "live-smoke",
        }
    )
    kubeconfig = output / "empty-kubeconfig.yaml"
    kubeconfig.write_text(
        'apiVersion: v1\nkind: Config\nclusters: []\nusers: []\ncontexts: []\ncurrent-context: ""\n'
    )
    env["KUBECONFIG"] = str(kubeconfig)

    # A test-only flow uses the existing tool-free reporting agent. No changes
    # are committed to CrewAI; the original infrastructure flows are not run.
    flow = sources / "crewai/src/auto_k8s_pilot/config/layers/flow-live-llm-smoke.yaml"
    flow.write_text("steps:\n  - run: explain_pods\n")
    env["DEFAULT_FLOW"] = "live-llm-smoke"

    def start(name, command, cwd, extra):
        with open(output / f"{name}.log", "w") as log:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env={**env, **extra},
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        children.append(process)
        return process

    def ready(url, process):
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(
                    "Service exited before readiness; inspect sanitized logs"
                )
            try:
                with urllib.request.urlopen(url, timeout=2) as response:
                    if response.status == 200:
                        return
            except OSError:
                pass
            time.sleep(0.2)
        raise RuntimeError("Service readiness timed out")

    try:
        fastapi = sources / "fastapi"
        crewai = sources / "crewai"
        ui = sources / "ui"
        api_process = start(
            "fastapi",
            [
                str(fastapi / ".venv/bin/python"),
                "-m",
                "uvicorn",
                "app.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                "8134",
            ],
            fastapi,
            {
                "DATABASE_URL": f"sqlite:///{output}/chat.sqlite3",
                "OTEL_SERVICE_NAME": "chat-api-live-smoke",
            },
        )
        crew_process = start(
            "crewai",
            [
                str(crewai / ".venv/bin/python"),
                "-m",
                "uvicorn",
                "auto_k8s_pilot.api:app",
                "--host",
                "127.0.0.1",
                "--port",
                "8135",
            ],
            crewai,
            {"OTEL_SERVICE_NAME": "crewai-live-smoke"},
        )
        ui_process = start(
            "ui",
            [
                "node",
                "node_modules/next/dist/bin/next",
                "start",
                "--hostname",
                "127.0.0.1",
                "--port",
                "3101",
            ],
            ui,
            {
                "CHAT_API_URL": "http://127.0.0.1:8134",
                "CREWAI_API_URL": "http://127.0.0.1:8135",
            },
        )
        ready("http://127.0.0.1:8134/health", api_process)
        ready("http://127.0.0.1:8135/health", crew_process)
        ready("http://127.0.0.1:3101/automation", ui_process)

        # Reuse the existing direct FastAPI runtime smoke (two model calls).
        subprocess.run(
            [
                "sh",
                str(Path(__file__).resolve().parents[1] / "fastapi-runtime-smoke.sh"),
                "http://127.0.0.1:8134",
            ],
            env=env,
            check=True,
            capture_output=True,
            text=True,
            timeout=180,
        )
        browser = subprocess.run(
            [
                "node",
                str(Path(__file__).with_name("browser.mjs")),
                str(ui),
                str(output),
            ],
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=240,
        )
        if browser.returncode:
            # Browser assertions can include model output, but never the key.
            raise RuntimeError(
                "Browser live smoke failed: "
                + browser.stderr[-4000:].replace(key, "[REDACTED]")
            )
        proof = json.loads((output / "browser.json").read_text())
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if all(
                any(
                    s["trace_id"] == t["trace_id"] and s["service"] == t["service"]
                    for s in spans
                )
                for t in proof["traces"]
            ):
                break
            time.sleep(0.2)
        if not all(
            any(
                s["trace_id"] == t["trace_id"] and s["service"] == t["service"]
                for s in spans
            )
            for t in proof["traces"]
        ):
            raise RuntimeError("UI trace IDs did not appear in OTLP export")
        usage = gate.snapshot()
        if usage["requests"] != 6 or usage["statuses"] != [200] * 6:
            raise RuntimeError("Expected six successful bounded OpenAI requests")
        summary.update(result="PASS", browser=proof, otlp_trace_ids_matched=True)
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        # Do not leak subprocess stdout/stderr or request headers by default.
        summary["error"] = str(error).replace(key, "[REDACTED]")[:4000]
    finally:
        for process in reversed(children):
            if process.poll() is None:
                process.terminate()
        for process in reversed(children):
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        server.shutdown()
        server.server_close()
        summary["usage"] = gate.snapshot()
        summary["exported_spans"] = len(spans)
        summary["revisions"] = {
            name: subprocess.check_output(
                ["git", "-C", str(sources / name), "rev-parse", "HEAD"], text=True
            ).strip()
            for name in ("fastapi", "crewai", "ui")
        }
        # Only a minimal summary is uploaded. Logs/DB/config are local to runner.
        (output / "summary.json").write_text(json.dumps(summary, indent=2))
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as report:
                report.write(
                    "## Live application smoke\n\n```json\n"
                    + json.dumps(summary, indent=2)
                    + "\n```\n"
                )
        print(json.dumps(summary))
    return 0 if summary["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

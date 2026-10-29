"""Runner-local test transport, not an application gateway.

Only this module receives the real key. Application processes get a dummy key
and loopback URL. One run can make at most six short gpt-4o-mini requests.
"""

import json
import threading
import urllib.error
import urllib.request


class GateError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


class BudgetGate:
    def __init__(self, upstream):
        self._upstream = upstream
        self._lock = threading.Lock()
        self._requests = 0
        self._statuses = []
        self._prompt_tokens = 0
        self._completion_tokens = 0

    def complete(self, body):
        if not isinstance(body, dict) or body.get("model") != "gpt-4o-mini":
            raise GateError(400, "Smoke only permits gpt-4o-mini")
        messages = body.get("messages")
        if not isinstance(messages, list) or not messages:
            raise GateError(400, "Messages are required")
        if any(
            not isinstance(m, dict)
            or m.get("role") not in ("system", "user", "assistant")
            or not isinstance(m.get("content"), str)
            for m in messages
        ):
            raise GateError(400, "Smoke only permits text messages")
        if sum(len(m["content"]) for m in messages) > 24000:
            raise GateError(413, "Smoke prompt exceeds 24000 characters")
        payload = {
            key: body[key]
            for key in ("model", "messages", "temperature", "stop")
            if key in body
        }
        payload.update(max_tokens=128, n=1, stream=False)
        with self._lock:
            if self._requests >= 6:
                raise GateError(429, "Smoke request budget exhausted")
            self._requests += 1
        status, reply = self._upstream(payload)
        usage = reply.get("usage", {}) if isinstance(reply, dict) else {}
        with self._lock:
            self._statuses.append(status)
            self._prompt_tokens += int(usage.get("prompt_tokens", 0))
            self._completion_tokens += int(usage.get("completion_tokens", 0))
        return status, reply

    def snapshot(self):
        with self._lock:
            return {
                "model": "gpt-4o-mini",
                "requests": self._requests,
                "max_requests": 6,
                "max_output_tokens_per_request": 128,
                "prompt_tokens": self._prompt_tokens,
                "completion_tokens": self._completion_tokens,
                "statuses": list(self._statuses),
            }


def openai_upstream(key):
    def complete(payload):
        request = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions",
            data=json.dumps(payload).encode(),
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            # Never return/log the provider body: it can mention credentials.
            return error.code, {"error": {"message": f"OpenAI HTTP {error.code}"}}
        except (urllib.error.URLError, TimeoutError, ValueError):
            return 502, {"error": {"message": "OpenAI transport failed"}}

    return complete

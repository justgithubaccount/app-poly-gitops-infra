"""Offline behavior checks for the paid smoke guard; no provider calls."""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "live_smoke"))
from budget import BudgetGate, GateError


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

        def upstream(body):
            self.calls.append(body)
            return 200, {
                "choices": [{"message": {"content": "ok"}}],
                "usage": {
                    "prompt_tokens": 12,
                    "completion_tokens": 4,
                    "total_tokens": 16,
                },
            }

        self.gate = BudgetGate(upstream)
        self.body = {
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "Smoke"}],
        }

    def test_caps_completion_and_drops_unneeded_parameters(self):
        self.gate.complete(
            {
                **self.body,
                "max_tokens": 9000,
                "max_completion_tokens": 9000,
                "n": 100,
                "stream": True,
                "user": "must-not-forward",
            }
        )
        self.assertEqual(self.calls[0]["max_tokens"], 128)
        self.assertEqual(self.calls[0]["n"], 1)
        self.assertFalse(self.calls[0]["stream"])
        self.assertNotIn("max_completion_tokens", self.calls[0])
        self.assertNotIn("user", self.calls[0])

    def test_stops_before_seventh_upstream_call(self):
        for _ in range(6):
            self.gate.complete(self.body)
        with self.assertRaises(GateError) as caught:
            self.gate.complete(self.body)
        self.assertEqual(caught.exception.status, 429)
        self.assertEqual(len(self.calls), 6)

    def test_rejects_other_models_and_oversized_or_invalid_messages(self):
        for body in [
            {**self.body, "model": "expensive-other-model"},
            {**self.body, "messages": []},
            {**self.body, "messages": [{"role": "user", "content": "x" * 24001}]},
            {
                **self.body,
                "messages": [{"role": "user", "content": [{"type": "image_url"}]}],
            },
        ]:
            with self.assertRaises(GateError):
                self.gate.complete(body)
        self.assertEqual(self.calls, [])

    def test_reports_only_usage_and_status_not_prompts_or_replies(self):
        self.gate.complete(self.body)
        snapshot = self.gate.snapshot()
        self.assertEqual(snapshot["requests"], 1)
        self.assertEqual(snapshot["prompt_tokens"], 12)
        self.assertEqual(snapshot["completion_tokens"], 4)
        self.assertEqual(snapshot["statuses"], [200])
        self.assertNotIn("Smoke", json.dumps(snapshot))
        self.assertNotIn("choices", snapshot)

    def test_failed_upstream_call_consumes_budget_without_retry(self):
        attempts = []

        def failing(body):
            attempts.append(body)
            return 401, {"error": {"message": "OpenAI HTTP 401"}}

        gate = BudgetGate(failing)
        self.assertEqual(gate.complete(self.body)[0], 401)
        self.assertEqual(gate.snapshot()["requests"], 1)
        self.assertEqual(gate.snapshot()["statuses"], [401])
        self.assertEqual(len(attempts), 1)


if __name__ == "__main__":
    unittest.main()

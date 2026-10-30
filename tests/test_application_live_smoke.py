"""Offline behavior checks for the paid smoke guard; no provider calls."""

import json
import re
import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts" / "live_smoke"))
from budget import BudgetGate, GateError


REPO_ROOT = Path(__file__).resolve().parents[1]


class SourceRevisionContractTests(unittest.TestCase):
    def setUp(self):
        workflow_path = REPO_ROOT / ".github/workflows/application-live-smoke.yaml"
        self.workflow = yaml.load(workflow_path.read_text(), Loader=yaml.BaseLoader)
        self.job = self.workflow["jobs"]["live"]
        self.steps = self.job["steps"]

    def test_all_external_sources_use_one_immutable_revision_each(self):
        expected = {
            "justgithubaccount/app-poly-gitops-fastapi": "CHAT_BACKEND_REVISION",
            "justgithubaccount/app-poly-gitops-crewai": "CREWAI_REVISION",
            "justgithubaccount/app-poly-gitops-ui": "UI_REVISION",
        }

        self.assertEqual(set(self.job["env"]), set(expected.values()))
        for revision in self.job["env"].values():
            self.assertRegex(revision, re.compile(r"^[0-9a-f]{40}$"))

        external_checkouts = {
            step["with"]["repository"]: step
            for step in self.steps
            if step.get("uses") == "actions/checkout@v7"
            and "repository" in step.get("with", {})
        }
        self.assertEqual(set(external_checkouts), set(expected))
        for repository, variable in expected.items():
            checkout = external_checkouts[repository]
            self.assertEqual(checkout["with"]["ref"], "${{ env.%s }}" % variable)
            self.assertEqual(checkout["with"]["persist-credentials"], "false")

    def test_revision_verification_precedes_provider_secret_exposure(self):
        verify_index = next(
            index
            for index, step in enumerate(self.steps)
            if step.get("name") == "Verify audited source revisions before exposing the key"
        )
        secret_index = next(
            index
            for index, step in enumerate(self.steps)
            if "OPENAI_API_KEY" in step.get("env", {})
        )
        self.assertLess(verify_index, secret_index)

        verify_command = self.steps[verify_index]["run"]
        for variable in ("CHAT_BACKEND_REVISION", "CREWAI_REVISION", "UI_REVISION"):
            self.assertIn('${%s}' % variable, verify_command)


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

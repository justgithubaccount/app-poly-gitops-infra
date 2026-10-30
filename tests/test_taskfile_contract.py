"""Offline contracts for Taskfile entrypoints and repository automation."""

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
TASKFILE = REPO_ROOT / "Taskfile.yaml"


class TaskfileContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document = yaml.load(TASKFILE.read_text(), Loader=yaml.BaseLoader)
        cls.tasks = cls.document["tasks"]

    def test_every_entrypoint_has_an_explicit_side_effect_class(self):
        expected = {
            "default": "read-only",
            "init": "mutating",
            "refresh": "mutating",
            "plan": "read-only",
            "kubeconfig": "local-write",
            "bootstrap": "mutating",
            "argocd-password": "secret-sensitive",
            "argocd-port-forward": "read-only",
            "app-of-apps": "mutating",
            "destroy": "destructive",
            "up": "mutating",
            "status": "read-only",
            "sync-wait": "read-only",
            "nodes": "read-only",
            "seal": "secret-sensitive",
            "seal:openrouter": "secret-sensitive",
            "seal:github": "secret-sensitive",
            "seal:postgres": "secret-sensitive",
            "seal:postgree": "secret-sensitive",
            "twc:versions": "read-only",
            "twc:presets": "read-only",
            "twc:list": "read-only",
            "twc:kubeconfig": "local-write",
            "twc:show": "read-only",
        }
        self.assertEqual(set(self.tasks), set(expected))
        for name, classification in expected.items():
            self.assertTrue(
                self.tasks[name]["desc"].startswith(f"[{classification}] "),
                f"{name} must be classified as {classification}",
            )

    def test_every_referenced_script_exists_and_is_executable(self):
        references = set(re.findall(r"\./(scripts/[A-Za-z0-9._/-]+)", TASKFILE.read_text()))
        self.assertTrue(references)
        for reference in references:
            path = REPO_ROOT / reference
            self.assertTrue(path.is_file(), reference)
            self.assertTrue(path.stat().st_mode & 0o111, reference)

    def test_nodes_is_direct_read_only_kubectl(self):
        commands = "\n".join(self.tasks["nodes"]["cmds"])
        self.assertIn("kubectl --kubeconfig={{.KUBECONFIG_PATH}} get nodes -o wide", commands)
        self.assertNotIn("scripts/", commands)

    def test_secret_tasks_pass_environment_names_not_values(self):
        text = TASKFILE.read_text() + (REPO_ROOT / "scripts/seal.sh").read_text()
        for forbidden in ("$OPENROUTER_API_KEY", "$GITHUB_PAT", "$DATABASE_URL", "--from-literal"):
            self.assertNotIn(forbidden, text)
        self.assertEqual(
            self.tasks["seal:postgree"]["cmds"],
            ["./scripts/seal.sh chat-postgree chat-api DATABASE_URL"],
        )

    def test_task_dry_runs_do_not_expand_secret_values(self):
        task = shutil.which("task")
        self.assertIsNotNone(task, "Task CLI must be installed for contract tests")
        environment = {
            **os.environ,
            "OPENROUTER_API_KEY": "contract-dummy-openrouter-secret",
            "GITHUB_PAT": "contract-dummy-github-secret",
            "GITHUB_USERNAME": "contract-user",
            "GITHUB_REPO_URL": "https://github.com/example/repo",
            "DATABASE_URL": "postgresql://contract-dummy-database-secret",
        }
        for task_name in ("seal:openrouter", "seal:github", "seal:postgres", "seal:postgree"):
            result = subprocess.run(
                [task, "--dry", task_name],
                cwd=REPO_ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=True,
            )
            output = result.stdout + result.stderr
            self.assertNotIn("contract-dummy", output)

    def test_bootstrap_renders_chart_once_and_retries_the_rendered_file(self):
        commands = "\n".join(self.tasks["bootstrap"]["cmds"])
        self.assertEqual(commands.count("helm template"), 1)
        self.assertIn("mktemp", commands)
        self.assertIn("Retrying the same rendered manifest once", commands)

    def test_app_of_apps_uses_a_guarded_immutable_revision(self):
        self.assertEqual(self.document["vars"]["GITOPS_REVISION"], "v1.5.0")
        commands = "\n".join(self.tasks["app-of-apps"]["cmds"])
        self.assertNotIn("/main/", commands)
        self.assertIn("{{.GITOPS_REVISION}}", commands)
        self.assertIn(".spec.source.targetRevision", commands)
        self.assertIn("requires a release tag or 40-character commit SHA", commands)

    def test_app_of_apps_rejects_a_branch_before_any_download(self):
        task = shutil.which("task")
        self.assertIsNotNone(task, "Task CLI must be installed for contract tests")
        result = subprocess.run(
            [task, "app-of-apps", "GITOPS_REVISION=main"],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "requires a release tag or 40-character commit SHA",
            result.stdout + result.stderr,
        )

    def test_required_pins_and_workflows_are_preserved(self):
        self.assertIn('ref=v0.1.0', (REPO_ROOT / "terraform/timeweb/main.tf").read_text())
        self.assertIn(
            "targetRevision: v1.5.0",
            (REPO_ROOT / "bootstrap/argocd/gitops-smoke-root.yaml").read_text(),
        )
        self.assertIn(
            "targetRevision: main",
            (REPO_ROOT / "bootstrap/argocd/values.yaml").read_text(),
        )
        workflows = list((REPO_ROOT / ".github/workflows").glob("*.yaml"))
        self.assertEqual(len(workflows), 7)

    def test_ci_uses_pinned_tools_and_enforces_security_scan(self):
        workflow = yaml.load(
            (REPO_ROOT / ".github/workflows/ci.yaml").read_text(),
            Loader=yaml.BaseLoader,
        )
        steps = workflow["jobs"]["validate"]["steps"]
        task_setup = next(step for step in steps if step.get("name") == "Install Task")
        terraform = next(step for step in steps if step.get("name") == "Setup Terraform")
        shellcheck = next(step for step in steps if step.get("name") == "Check shell scripts")
        tfsec = next(
            step for step in workflow["jobs"]["security"]["steps"] if step.get("name") == "tfsec"
        )
        self.assertEqual(
            task_setup["uses"],
            "arduino/setup-task@b91d5d2c96a56797b48ac1e0e89220bf64044611",
        )
        self.assertEqual(task_setup["with"]["version"], "3.54.0")
        self.assertEqual(
            terraform["uses"],
            "hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd",
        )
        self.assertEqual(terraform["with"]["terraform_version"], "1.13.5")
        self.assertEqual(
            shellcheck["uses"],
            "ludeeus/action-shellcheck@00cae500b08a931fb5698e11e79bfbd38e612a38",
        )
        self.assertEqual(shellcheck["with"]["version"], "v0.11.0")
        self.assertEqual(tfsec["with"]["version"], "v1.28.14")
        self.assertEqual(
            tfsec["uses"],
            "aquasecurity/tfsec-action@b466648d6e39e7c75324f25d83891162a721f2d6",
        )
        self.assertNotEqual(tfsec["with"].get("soft_fail"), "true")


if __name__ == "__main__":
    unittest.main()

# Taskfile and operator contracts

`Taskfile.yaml` is the supported local operator interface. Every entrypoint has
an explicit side-effect class. `task --list-all` shows the class before any
command runs; CI also verifies task names, dependencies, referenced scripts,
kubeconfig use, immutable revisions, and critical tool versions.

## Side-effect matrix

| Class | Tasks | Contract |
| --- | --- | --- |
| `read-only` | `default`, `plan`, `argocd-port-forward`, `status`, `sync-wait`, `nodes`, `twc:versions`, `twc:presets`, `twc:list`, `twc:show` | Reads local configuration or remote status; does not intentionally change infrastructure. Port-forward holds a local listener. `plan` may refresh remote data/state in memory. |
| `local-write` | `kubeconfig`, `twc:kubeconfig` | Writes `~/.kube/timeweb-config` and sets mode `0600`; does not mutate the cluster. |
| `mutating` | `init`, `refresh`, `bootstrap`, `app-of-apps`, `up` | Changes Terraform state/cloud resources or Kubernetes desired state. Review the command and pins first. |
| `destructive` | `destroy` | Destroys resources tracked by the selected Terraform state after an interactive prompt. |
| `secret-sensitive` | `argocd-password`, `seal`, `seal:openrouter`, `seal:github`, `seal:postgres`, `seal:postgree` | Prints or transforms sensitive material. `seal:*` reads values from environment variables and outputs a SealedSecret; it does not apply it. |

All Kubernetes entrypoints use `KUBECONFIG_PATH`, which defaults to
`~/.kube/timeweb-config`. Terraform entrypoints use `terraform/timeweb`.

## Compatibility and consolidation

| Previous interface | Current interface | Compatibility / rollback |
| --- | --- | --- |
| `nodes` called missing `scripts/check-nodes.sh` | Direct read-only `kubectl get nodes -o wide` | Revert the Taskfile command only if a maintained script with additional behavior is restored. |
| `argocd-sync-check.sh` duplicated polling logic | Compatibility wrapper delegates to `wait-for-argocd-application.sh` | Existing path, default kubeconfig (`~/.kube/timeweb-config`), explicit `KUBECONFIG`, defaults (`dev-cluster`, 120 seconds), and success/failure exit behavior remain. Revert the wrapper to restore legacy formatting only. |
| Bootstrap rendered the chart twice on retry | Render once; retry the same temporary file | Apply behavior and one retry remain. Revert the bootstrap command to restore the old re-rendering behavior. |
| Root application fetched `main` | `GITOPS_REVISION=v1.5.1`, guarded to a release tag or full SHA | Override with a reviewed release/SHA; revert the variable and command to resume branch tracking. |
| `seal:*` passed `KEY=value` via argv | `KEY[:ENV_VAR]`; value read from environment and piped to kubeseal | `KEY=value` is intentionally rejected. `seal:postgres` creates `chat-postgres`; legacy `seal:postgree` retains `chat-postgree` for the existing GitOps consumer. |

The repository workflows call `wait-for-argocd-application.sh` directly. The
legacy `argocd-sync-check.sh` path and misspelled PostgreSQL task are retained
because external manual callers cannot be proven absent. SealedSecret helpers
remain optional: no active dev/smoke workflow invokes them, and their output is
not applied automatically.

The self-managed Argo CD values source remains on `main` as a documented
temporary exception. The only existing release, `v0.1.0`, also points that
source to `main`, so selecting the tag does not establish a stable self-pin. A
future release can replace this exception after its tagged values contain the
new immutable revision.

## Offline validation

The following checks do not provision infrastructure or contact Kubernetes:

~~~bash
task --list-all --json > /dev/null
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/test_ephemeral_smoke.sh
bash tests/test_timeweb_floating_ip_cleanup.sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/timeweb init -backend=false -input=false
terraform -chdir=terraform/timeweb validate
tfsec terraform/timeweb
~~~

Do not use `task up`, `task init`, `task refresh`, `task bootstrap`,
`task app-of-apps`, `task destroy`, Terraform plan/apply/destroy, or a Timeweb
workflow as a documentation or CI validation step.

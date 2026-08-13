# Charmed Airflow UATs

Automated User Acceptance Tests (UATs) for [Charmed Airflow](https://charmhub.io/airflow-k8s).

This repo deploys Charmed Airflow via Terraform and runs end-to-end checks against a real deployment, covering the local executor and the Kubernetes executor.

## What's covered

| Suite | What it checks | Command |
|---|---|---|
| **Core operations** | Deploys with the local executor, logs into the Airflow API, lists DAGs, triggers a DAG run, and waits for it to succeed | `just uats-core-operations` |
| **Kubernetes executor** | Deploys with the Kubernetes executor, triggers a DAG run that executes as a Kubernetes pod, and waits for it to succeed | *(run via `just uats-kubernetes-executor`, see below)* |

Both run automatically on every pull request via [`.github/workflows/uats.yaml`](.github/workflows/uats.yaml).

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.12.2
- [just](https://just.systems/)
- [uv](https://docs.astral.sh/uv/)
- [juju](https://juju.is/) >= 3.6 with a bootstrapped k8s controller
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.github.io/jq/)
- [goss](https://github.com/goss-org/goss) (used to validate the running deployment)

## Setup

Bootstrap a Juju controller on Kubernetes:

```bash
sudo snap install concierge --classic
sudo concierge prepare -p k8s
```

## Deploying manually

### Local executor (default)

```bash
just deploy <model_name>
just destroy <model_name>
```

### Kubernetes executor

```bash
just deploy-k8s-executor <model_name>
just destroy <model_name>
```

Deployment is driven by the Terraform module in [`terraform/`](terraform), which:
- Deploys Charmed Airflow via the `charmed-airflow` Terraform module, generating and wiring up a Fernet key secret
- Optionally deploys and integrates [`git-integrator`](https://github.com/canonical/git-integrator) (`deploy_git_integrator = true`), used to load DAGs from a git repository — enabled by default for the Kubernetes executor test config ([`terraform/test/terraform_test_kubernetes_executor.tfvars`](terraform/test/terraform_test_kubernetes_executor.tfvars))

## Running the UATs

Each suite deploys its own environment, runs its checks, and tears itself down on failure.

```bash
# Core operations (local executor)
just uats-core-operations

# Kubernetes executor
just uats-kubernetes-executor

```

Runtime checks against the live deployment (API connectivity, DAG listing, triggering a run) are
defined as [goss](https://github.com/goss-org/goss) specs in [`tests/goss/`](tests/goss); the
identity suite is a `pytest` test in [`tests/test_identity.py`](tests/test_identity.py).

## Lint & format

```bash
just lint            # Terraform lint (tflint)
just lint-python      # Python lint (ruff, codespell)
just fmt              # Terraform fmt
just format-python     # Python format (ruff)
```

## Debugging

```bash
just get-system-state
```

Prints Juju status (with relations and storage) for every model, plus disk usage, k8s status, and
current Terraform state — useful when a UAT run fails in CI.

## Repository layout

```
terraform/     Terraform module deploying Charmed Airflow, git-integrator, and identity integrations
tests/         UAT test code, sample DAG, and goss validation specs
justfile       All deploy / test / lint / debug commands
```
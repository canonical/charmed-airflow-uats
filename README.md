# Charmed Airflow UATs

Automated User Acceptance Tests (UATs) for [Charmed Airflow](https://charmhub.io/airflow-k8s).

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.12.2
- [just](https://just.systems/)
- [uv](https://docs.astral.sh/uv/)
- [juju](https://juju.is/) >= 3.6 with a bootstrapped k8s controller
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.github.io/jq/)
- [goss](https://github.com/goss-org/goss)

## Setup

Bootstrap a Juju controller on Kubernetes:

```bash
sudo snap install concierge --classic
sudo concierge prepare -p k8s
```

## Testing instructions

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

### Goss smoke tests

[goss](https://github.com/goss-org/goss) checks verify a deployment two ways:

- **Application status** - each Charmed Airflow application (`postgresql`,`pgbouncer`, `airflow-coordinator`, `airflow-api-server`, `airflow-scheduler`, `airflow-triggerer`, `airflow-dag-processor`) reaches `active` status via `juju wait-for application`.

- **API functionality** - the Airflow API server actually responds and reports healthy (`/api/v2/monitor/health`, which reflects the metadatabase, scheduler, triggerer, and dag-processor heartbeats), and reports the expected running version (`/api/v2/version`).

These run as part of the `uats` recipes, which deploy, validate, and tear down the model in one step:

```bash
# Local executor
just uats <model_name>

# Kubernetes executor
just uats-k8s-executor <model_name>
```

Requires the [goss](https://github.com/goss-org/goss) binary to be installedand available on `PATH`.

## Lint & Format

```bash
just lint
just format
```

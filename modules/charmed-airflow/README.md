# charmed-airflow

Terraform module that deploys Charmed Airflow on Kubernetes using the Juju provider.

## What it deploys

- `postgresql-k8s` (3 units) — metadata database
- `pgbouncer-k8s` — connection pooler
- `airflow-coordinator-k8s` — central coordinator
- `airflow-api-server-k8s` — REST API and web UI
- `airflow-scheduler-k8s` — DAG scheduler
- `airflow-triggerer-k8s` — deferred task triggerer
- `airflow-dag-processor-k8s` — DAG file processor

## Usage

This module is not meant to be used directly. Use the `charmed-airflow-uats` wrapper module instead, which handles secret creation and fernet key configuration.

If you do use it directly, you must pass `model_uuid` and handle the fernet key secret yourself:

```hcl
module "charmed_airflow" {
  source     = "./modules/charmed-airflow"
  model_uuid = "<juju-model-uuid>"
  postgresql = {
    profile = "testing"
  }
}
```

## Inputs

| Variable | Description | Default |
|---|---|---|
| `model_uuid` | UUID of the Juju model to deploy into | required |
| `postgresql` | postgresql-k8s charm inputs | `{}` |
| `pgbouncer` | pgbouncer-k8s charm inputs | `{}` |
| `airflow_coordinator` | airflow-coordinator-k8s charm inputs | `{}` |
| `airflow_api_server` | airflow-api-server-k8s charm inputs | `{}` |
| `airflow_scheduler` | airflow-scheduler-k8s charm inputs | `{}` |
| `airflow_triggerer` | airflow-triggerer-k8s charm inputs | `{}` |
| `airflow_dag_processor` | airflow-dag-processor-k8s charm inputs | `{}` |

## Outputs

| Output | Description |
|---|---|
| `applications` | Names and details of all deployed applications |

## Development

```bash
# Lint
just lint

# Format
just format

# Run integration tests
just integration
```

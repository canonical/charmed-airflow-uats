# charmed-airflow-uats

Wrapper Terraform module for deploying Charmed Airflow for UAT testing. Handles fernet key secret creation, charm deployment, and post-deploy configuration in a single `just deploy` command.

## What it does

1. Generates a cryptographically secure fernet key (`random_bytes`)
2. Stores it as a Juju secret (`juju_secret`)
3. Deploys Charmed Airflow via the `charmed-airflow` module
4. Grants the secret to the coordinator (`juju_access_secret`)
5. Configures the coordinator with the secret URI (`juju config`)

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.12.2
- [just](https://just.systems/)
- [juju](https://juju.is/) with a bootstrapped controller
- [jq](https://jqlang.github.io/jq/)

## Usage

```bash
# Deploy Charmed Airflow (creates model, deploys, configures fernet key)
just deploy test/terraform_test.tfvars

# Destroy everything
just destroy test/terraform_test.tfvars
```

## Inputs

| Variable | Description | Default |
|---|---|---|
| `model_uuid` | UUID of the Juju model (injected at runtime by justfile) | required |
| `postgresql` | postgresql-k8s charm inputs | `{}` |
| `pgbouncer` | pgbouncer-k8s charm inputs | `{}` |
| `airflow_coordinator` | airflow-coordinator-k8s charm inputs | `{}` |
| `airflow_api_server` | airflow-api-server-k8s charm inputs | `{}` |
| `airflow_scheduler` | airflow-scheduler-k8s charm inputs | `{}` |
| `airflow_triggerer` | airflow-triggerer-k8s charm inputs | `{}` |
| `airflow_dag_processor` | airflow-dag-processor-k8s charm inputs | `{}` |

## Test variables

`test/terraform_test.tfvars` contains non-secret overrides for UAT runs:

```hcl
postgresql = {
  profile = "testing"
}
```

`model_uuid` is injected automatically at runtime by `just deploy` — do not commit it.

## Known limitations

The Juju Terraform provider does not support setting `type: secret` charm config options via `juju_application.config`. The fernet key config step is therefore handled as a post-apply `juju config` call in the justfile.

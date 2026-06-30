# Charmed Airflow UATs

Automated User Acceptance Tests (UATs) for [Charmed Airflow](https://charmhub.io/airflow-k8s).

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.12.2
- [just](https://just.systems/)
- [uv](https://docs.astral.sh/uv/)
- [juju](https://juju.is/) >= 3.6 with a bootstrapped k8s controller
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.github.io/jq/)

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

## Lint & Format

```bash
just lint
just format
```

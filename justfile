# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set export

[private]
default:
    @just --list

[private]
destroy-model model_name:
    juju destroy-model --no-prompt --destroy-storage {{model_name}} --force || true

[private]
add-model model_name: (destroy-model model_name)
    juju add-model {{model_name}}

[private]
initialize:
    #!/usr/bin/bash
    if [ ! -d "terraform/.terraform" ]; then
        terraform -chdir=terraform init
    fi

[private]
apply model_name variables_file="": (initialize)
    #!/usr/bin/bash
    set -euxo pipefail
    MODEL_UUID=$(juju show-model {{model_name}} --format=json | jq -r '."{{model_name}}"["model-uuid"]')
    if [ -n "{{variables_file}}" ]; then
        terraform -chdir=terraform apply -auto-approve \
            -var="model_uuid=${MODEL_UUID}" \
            -var-file="../{{variables_file}}"
    else
        terraform -chdir=terraform apply -auto-approve \
            -var="model_uuid=${MODEL_UUID}"
    fi

[private]
wait-for-active model_name:
    #!/usr/bin/env bash
    set -euxo pipefail

    if ! juju wait-for model {{model_name}} \
        --query='forEach(units,  unit => (unit.workload-status == "active"))' \
        --timeout=15m; then
        echo "Timed out waiting for model {{model_name}} to become active" >&2
        exit 1
    fi
    echo "Model {{model_name}} is active."

[private]
configure-fernet-key model_name:
    #!/usr/bin/bash
    set -euxo pipefail
    SECRET_URI=$(juju show-secret fernet-key-secret -m {{model_name}} --format=json | jq -r 'keys[0] | "secret:" + .')
    juju config airflow-coordinator fernet_key_secret="${SECRET_URI}" -m {{model_name}}

[private]
create-namespace ns:
    #!/usr/bin/bash
    set -euxo pipefail
    command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
    kubectl create namespace "{{ ns }}" || true

# Terraform fmt
fmt: (initialize)
    terraform -chdir=terraform fmt -recursive

# Terraform validate
validate: (initialize)
    terraform -chdir=terraform validate

# Terraform lint
lint:
    tflint --chdir=terraform

# Lint Python source code
lint-python:
    uv tool run --python 3.12 tox -e lint

# Format Python source code
format-python:
    uv tool run --python 3.12 tox -e format

# Deploy Charmed Airflow with local executor (default)
deploy model_name="airflow":
    just add-model {{model_name}}
    just apply {{model_name}}
    just configure-fernet-key {{model_name}}
    just wait-for-active {{model_name}}
    @echo "Charmed Airflow deployed successfully in model {{model_name}}."

# Deploy Charmed Airflow with Kubernetes executor
deploy-k8s-executor model_name="airflow":
    just create-namespace "airflow-executor-workers"
    just add-model {{model_name}}
    just apply {{model_name}} "terraform/test/terraform_test_kubernetes_executor.tfvars"
    just configure-fernet-key {{model_name}}
    just wait-for-active {{model_name}}
    @echo "Charmed Airflow deployed successfully in model {{model_name}}."

# Print system state for debugging (juju status, k8s, disk)
get-system-state:
    #!/usr/bin/bash
    df -h
    echo "---"
    for model in $(juju models --format=json | jq -r '.models[]."short-name"'); do
        echo "=== Model: ${model} ==="
        juju status --model "${model}" --color --relations --storage || true
        echo "---"
    done
    sudo k8s status || true
    echo "---"
    terraform -chdir=terraform state list || true

# Destroy Charmed Airflow deployment
destroy model_name="airflow":
    #!/usr/bin/bash
    set -euxo pipefail
    if MODEL_UUID=$(juju show-model {{model_name}} --format=json | jq -r '."{{model_name}}"["model-uuid"]' 2>/dev/null); then
        terraform -chdir=terraform destroy -auto-approve \
            -var="model_uuid=${MODEL_UUID}" || true
    fi
    terraform -chdir=terraform state rm $(terraform -chdir=terraform state list) || true
    just destroy-model {{model_name}}

# Execute the UATs for the Airflow Identity integration
uats-identity airflow_model_name="" identity_model_name="":
    #!/usr/bin/bash
    set -euxo pipefail

    # TODO: uncomment once ready
    # just deploy ${airflow_model_name}

    # just wait-for-active ${airflow_model_name}
    # just wait-for-active ${identity_model_name}

    uv tool run --python 3.12 tox -e uats-identity -- \
        --airflow-model="${airflow_model_name:-airflow}" \
        --identity-model="${identity_model_name:-identity}"

uats airflow_model_name="" identity_model_name="":
    just uats-identity ${airflow_model_name} ${identity_model_name}

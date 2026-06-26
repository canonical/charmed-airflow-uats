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

    timeout=1200
    elapsed=0
    interval=10
    while [ $elapsed -lt $timeout ]; do
        if juju wait-for model {{model_name}} \
            --query='forEach(applications, app => app.status == "active")' \
            --timeout=${interval}s 2>/dev/null; then
            exit 0
        fi
        elapsed=$((elapsed + interval))
    done
    echo "Timed out waiting for model to become active"
    exit 1

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
    kubectl create namespace "{{ ns }}" --dry-run=client -o yaml | kubectl apply -f -

# Lint source code
lint:
    tox -e lint

# Format source code
format:
    tox -e format

# Deploy Charmed Airflow with local executor (default)
deploy model_name: (add-model model_name) (apply model_name) (configure-fernet-key model_name) (wait-for-active model_name)
    @echo "Charmed Airflow deployed successfully in model {{model_name}}."

# Deploy Charmed Airflow with Kubernetes executor
deploy-k8s-executor model_name: (create-namespace "airflow-executor-workers") (add-model model_name) (apply model_name "terraform/test/terraform_test_kubernetes_executor.tfvars") (configure-fernet-key model_name) (wait-for-active model_name)
    @echo "Charmed Airflow deployed successfully in model {{model_name}}." 

# Destroy Charmed Airflow deployment
destroy model_name:
    #!/usr/bin/bash
    set -euxo pipefail
    if MODEL_UUID=$(juju show-model {{model_name}} --format=json | jq -r '."{{model_name}}"["model-uuid"]' 2>/dev/null); then
        terraform -chdir=terraform destroy -auto-approve \
            -var="model_uuid=${MODEL_UUID}" || true
    fi
    terraform -chdir=terraform state list | xargs -r terraform -chdir=terraform state rm
    just destroy-model {{model_name}}


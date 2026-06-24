# Copyright 2025 Canonical Ltd.
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
validate_test_tfvars model_name variables_file:
    #!/usr/bin/bash
    set -euxo pipefail
    sed -i '/^model_uuid[[:space:]]*=/d' "${variables_file}"
    MODEL_UUID=$(juju show-model {{model_name}} --format=json | jq -r '."{{model_name}}"["model-uuid"]')
    juju show-model "${MODEL_UUID}" >/dev/null 2>&1
    echo "model_uuid = \"${MODEL_UUID}\"" >> "${variables_file}"

[private]
initialize:
    #!/usr/bin/bash
    if [ ! -d "terraform/.terraform" ]; then
        terraform -chdir=terraform init
    fi

[private]
apply model_name variables_file: (initialize)
    terraform -chdir=terraform apply -auto-approve -var-file="../{{variables_file}}"

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
deploy model_name variables_file: (add-model model_name) (validate_test_tfvars model_name variables_file) (apply model_name variables_file) (configure-fernet-key model_name)
    @echo "Charmed Airflow deployed successfully in model {{model_name}}."

# Deploy Charmed Airflow with Kubernetes executor
deploy-k8s-executor model_name: (create-namespace "airflow-executor-workers")
    just deploy {{model_name}} terraform/test/terraform_test_kubernetes_executor.tfvars

# Destroy Charmed Airflow deployment
destroy model_name variables_file:
    #!/usr/bin/bash
    set -euxo pipefail
    if juju show-model {{model_name}} >/dev/null 2>&1; then
        just validate_test_tfvars {{model_name}} {{variables_file}}
    fi
    terraform -chdir=terraform destroy -auto-approve -var-file="../{{variables_file}}" || true
    terraform -chdir=terraform state list | xargs -r terraform -chdir=terraform state rm
    just destroy-model {{model_name}}
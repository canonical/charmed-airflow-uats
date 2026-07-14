# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set export

[private]
default:
    @just --list

[private]
destroy-model model_name:
    juju destroy-model --no-prompt --destroy-storage ${model_name} --force || true

[private]
add-model model_name: (destroy-model model_name)
    juju add-model ${model_name}

[private]
initialize:
    #!/usr/bin/bash
    if [ ! -d "terraform/.terraform" ]; then
        terraform -chdir=terraform init
    fi

[private]
apply airflow_model_name variables_file="" identity_model_name="": (initialize)
    #!/usr/bin/bash
    set -euxo pipefail

    AIRFLOW_MODEL_UUID=$(juju show-model ${airflow_model_name} --format=json | jq -r ".\"${airflow_model_name}\"[\"model-uuid\"]")
    IDENTITY_MODEL_UUID=$(juju show-model ${identity_model_name} --format=json | jq -r ".\"${identity_model_name}\"[\"model-uuid\"]")

    identity_options=""

    if [ -n "${IDENTITY_MODEL_UUID}" ]; then
        identity_options+=" -var identity_model_uuid=${IDENTITY_MODEL_UUID}"
    fi


    if [ -n "${variables_file}" ]; then
        terraform -chdir=terraform apply -auto-approve \
            -var "airflow_model_uuid=${AIRFLOW_MODEL_UUID}" \
            -var-file="../${variables_file}" \
            ${identity_options}
    else
        terraform -chdir=terraform apply -auto-approve \
            -var "airflow_model_uuid=${AIRFLOW_MODEL_UUID}" \
            ${identity_options}
    fi

[private]
wait-for-active model_name:
    #!/usr/bin/env bash
    set -euxo pipefail
    for i in {1..120}; do
        if juju wait-for model ${model_name} \
            --query='forEach(applications, app => app.status == "active")' \
            --timeout=10s 2>/dev/null; then
            exit 0
        fi
    done
    echo "Timed out waiting for model to become active"
    exit 1

[private]
configure-fernet-key model_name:
    #!/usr/bin/bash
    set -euxo pipefail
    SECRET_URI=$(juju show-secret fernet-key-secret -m ${model_name} --format=json | jq -r 'keys[0] | "secret:" + .')
    juju config airflow-coordinator fernet_key_secret="${SECRET_URI}" -m ${model_name}

[private]
create-namespace ns:
    #!/usr/bin/bash
    set -euxo pipefail
    command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
    kubectl create namespace "${ ns }" || true

# Lint source code
lint:
    uv tool run --python 3.12 tox -e lint

# Format source code
format:
    uv tool run --python 3.12 tox -e format

# Deploy Charmed Airflow with local executor (default)
deploy model_name identity_model_name="":
    just add-model ${model_name}

    just apply ${model_name} "" ${identity_model_name}

    just configure-fernet-key ${model_name}

    @echo "Charmed Airflow deployed successfully in model ${model_name}."

# Deploy Charmed Airflow with Kubernetes executor
deploy-k8s-executor airflow_model_name:
    just create-namespace "airflow-executor-workers"
    just add-model ${airflow_model_name}

    just apply ${airflow_model_name} "terraform/test/terraform_test_kubernetes_executor.tfvars"

    just configure-fernet-key ${airflow_model_name}

    @echo "Charmed Airflow deployed successfully in model ${airflow_model_name}."

# Deploy Canonical Identity Platform in a model
deploy-identity identity_model_name:
    juju add-model ${identity_model_name}

    juju deploy self-signed-certificates --channel 1/stable
    juju deploy traefik-k8s traefik \
        --channel latest/stable \
        --base ubuntu@20.04 \
        --trust

    juju deploy kratos \
        --channel latest/stable \
        --base ubuntu@22.04 \
        --trust

    juju deploy hydra \
        --channel latest/stable \
        --base ubuntu@22.04 \
        --trust

    juju deploy identity-platform-login-ui-operator \
        login-ui \
        --channel latest/stable \
        --base ubuntu@22.04 \
        --trust

    juju deploy postgresql-k8s \
        postgres \
        --channel 14/stable \
        --trust

    juju integrate self-signed-certificates:certificates traefik:certificates

    juju integrate traefik:traefik-route login-ui:public-route
    juju integrate traefik:traefik-route hydra:public-route
    juju integrate traefik:traefik-route kratos:public-route

    juju integrate postgres:database hydra:pg-database
    juju integrate postgres:database kratos:pg-database

    juju integrate hydra:hydra-endpoint-info kratos:hydra-endpoint-info
    juju integrate hydra:hydra-endpoint-info login-ui:hydra-endpoint-info
    juju integrate login-ui:ui-endpoint-info kratos:ui-endpoint-info
    juju integrate login-ui:ui-endpoint-info hydra:ui-endpoint-info

    @echo "Canonical Idenitty Platform deployed successfully in model ${identity_model_name}."

# Destroy Charmed Airflow deployment (and optionally the identity model)
destroy model_name identity_model_name="":
    #!/usr/bin/bash
    set -euxo pipefail

    EXTRA_VARS=""
    if [ -n "${identity_model_name}" ]; then
        if IDENTITY_UUID=$(juju show-model ${identity_model_name} --format=json | jq -r ".\"${identity_model_name}\"[\"model-uuid\"]" 2>/dev/null); then
            EXTRA_VARS="-var identity_model_uuid=${IDENTITY_UUID}"
        fi
    fi

    if MODEL_UUID=$(juju show-model ${model_name} --format=json | jq -r ".\"${model_name}\"[\"model-uuid\"]" 2>/dev/null); then
        terraform -chdir=terraform destroy -auto-approve \
            -var "airflow_model_uuid=${MODEL_UUID}" \
            ${EXTRA_VARS} || true
    fi

    terraform -chdir=terraform state rm $(terraform -chdir=terraform state list) || true

    just destroy-model ${model_name} || true

    if [ -n "${identity_model_name}" ]; then
        just destroy-model ${identity_model_name} || true
    fi

# Execute the UATs for the Airflow Identity integration
uats-identity airflow_model_name="airflow" identity_model_name="identity":
    #!/usr/bin/bash
    set -euxo pipefail

    just deploy-identity ${identity_model_name}
    just deploy ${airflow_model_name} ${identity_model_name}

    just wait-for-active ${identity_model_name}
    just wait-for-active ${airflow_model_name}

    uv tool run --python 3.12 tox -e uats-identity -- \
        --airflow-model="${airflow_model_name}" \
        --identity-model="${identity_model_name}"

uats airflow_model_name="airflow" identity_model_name="identity":
    just uats-identity ${airflow_model_name} ${identity_model_name}

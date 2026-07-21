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
    
    if [ -n "${identity_model_name}" ] && juju show-model "${identity_model_name}" > /dev/null 2>&1; then
        IDENTITY_MODEL_UUID=$(juju show-model ${identity_model_name} --format=json | jq -r ".\"${identity_model_name}\"[\"model-uuid\"]")
    else
        IDENTITY_MODEL_UUID=""
    fi

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

    if ! juju wait-for model ${model_name} \
        --query='forEach(units,  unit => (unit.workload-status == "active"))' \
        --timeout=15m; then
        echo "Timed out waiting for model ${model_name} to become active" >&2
        exit 1
    fi
    echo "Model ${model_name} is active."

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
    kubectl create namespace "${ns}" || true

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
# TODO: use terraform module to deploy the identity platform when feasible
# https://github.com/canonical/charmed-airflow-uats/issues/8
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

# Execute the Core Operations UATs for the Airflow
uats-core-operations airflow_model_name="airflow":
    #!/usr/bin/bash
    set -euxo pipefail

    # Installs airflowctl (pinned in uv.lock via the uats-core group)
    uv sync --active --group uats-core
    pod_name="airflow-api-server-0"
    api_url="http://localhost:8080"

    just deploy ${airflow_model_name}
    just wait-for-active ${airflow_model_name}

    # Wait for the credentials file to exist inside the pod before moving ahead
    echo "Waiting for ${pod_name} to finish initializing..."
    for _ in $(seq 1 60); do
        kubectl exec -n "${airflow_model_name}" "${pod_name}" -c airflow-api-server -- \
            test -f /opt/airflow/simple_auth_manager_passwords.json.generated 2>/dev/null && break
        sleep 5
    done

    # Port forward the API server directly to the pod so we can get the credentials and access token
    kubectl port-forward -n "${airflow_model_name}" "pod/${pod_name}" 8080:8080 &
    pf_pid=$!
    trap 'kill ${pf_pid} 2>/dev/null || true' EXIT

    # Wait for the webserver itself to actually respond, not just the local socket
    for _ in $(seq 1 30); do
        curl -sf --max-time 2 "${api_url}/api/v2/monitor/health" > /dev/null 2>&1 && break
        sleep 2
    done

    # Fetch the credentials from the pod and use them to get an access token for the API
    set +x
    credentials=$(kubectl exec -n "${airflow_model_name}" "${pod_name}" -c airflow-api-server -- \
        cat /opt/airflow/simple_auth_manager_passwords.json.generated)
    username=$(echo "${credentials}" | jq -r 'to_entries[0].key')
    password=$(echo "${credentials}" | jq -r 'to_entries[0].value')

    access_token=$(curl -sf -X POST "${api_url}/auth/token" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${username}\", \"password\": \"${password}\"}" | jq -r '.access_token')

    export AIRFLOW_CLI_TOKEN="${access_token}"
    set -x

    goss -g tests/goss/goss.yaml validate

# Execute the Kubernetes Executor UAT: trigger a DAG run that executes in a
# Kubernetes Pod and wait for it to complete.
uats-kubernetes-executor airflow_model_name="airflow":
    #!/usr/bin/bash
    set -euxo pipefail

    # Installs airflowctl (pinned in uv.lock via the uats-core group)
    uv sync --active --group uats-core

    pod_name="airflow-api-server-0"
    api_url="http://localhost:8080"

    just deploy-k8s-executor ${airflow_model_name}
    just wait-for-active ${airflow_model_name}

    # Wait for the credentials file before moving ahead
    echo "Waiting for ${pod_name} to finish initializing..."
    for _ in $(seq 1 60); do
        kubectl exec -n "${airflow_model_name}" "${pod_name}" -c airflow-api-server -- \
            test -f /opt/airflow/simple_auth_manager_passwords.json.generated 2>/dev/null && break
        sleep 5
    done

    kubectl port-forward -n "${airflow_model_name}" "pod/${pod_name}" 8080:8080 &
    pf_pid=$!
    trap 'kill ${pf_pid} 2>/dev/null || true' EXIT

    for _ in $(seq 1 30); do
        curl -sf --max-time 2 "${api_url}/api/v2/monitor/health" > /dev/null 2>&1 && break
        sleep 2
    done

    # Fetch credentials, generate a token, and log airflowctl in - kept out of
    # trace output since this repo is public.
    set +x
    credentials=$(kubectl exec -n "${airflow_model_name}" "${pod_name}" -c airflow-api-server -- \
        cat /opt/airflow/simple_auth_manager_passwords.json.generated)
    username=$(echo "${credentials}" | jq -r 'to_entries[0].key')
    password=$(echo "${credentials}" | jq -r 'to_entries[0].value')

    access_token=$(curl -sf -X POST "${api_url}/auth/token" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${username}\", \"password\": \"${password}\"}" | jq -r '.access_token')

    export AIRFLOW_CLI_TOKEN="${access_token}"
    uv run airflowctl auth login --api-url "${api_url}" --env production --skip-keyring
    set -x

    echo "Waiting for example_simplest_dag to be parsed..."
    for _ in $(seq 1 30); do
        if ! kill -0 "${pf_pid}" 2>/dev/null; then
            echo "Port-forward died, restarting..."
            kubectl port-forward -n "${airflow_model_name}" "pod/${pod_name}" 8080:8080 &
            pf_pid=$!
            sleep 3
        fi
        uv run airflowctl dags list --env production 2>/dev/null | \
            jq -e '.[] | select(.dag_id == "example_simplest_dag")' > /dev/null 2>&1 && break
        sleep 10
    done

    # The actual connectivity + operational check: goss triggers the DAG and
    # asserts it reaches success.
    goss -g tests/goss/goss-kubernetes-executor.yaml validate
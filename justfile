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

    AIRFLOW_MODEL_UUID=$(juju show-model ${airflow_model_name} --format=json | jq -er ".\"${airflow_model_name}\"[\"model-uuid\"]")
    
    if [ -n "${identity_model_name}" ] && juju show-model "${identity_model_name}" > /dev/null 2>&1; then
        IDENTITY_MODEL_UUID=$(juju show-model ${identity_model_name} --format=json | jq -er ".\"${identity_model_name}\"[\"model-uuid\"]")
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
    SECRET_URI=$(juju show-secret fernet-key-secret -m ${model_name} --format=json | jq -er 'keys[0] | "secret:" + .')
    juju config airflow-coordinator fernet_key_secret="${SECRET_URI}" -m ${model_name}

[private]
create-namespace ns:
    #!/usr/bin/bash
    set -euxo pipefail
    command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
    kubectl create namespace "${ns}" || true

[private]
fetch-access-token airflow_model_name pod_name="airflow-api-server-0" api_url="http://localhost:8080":
    #!/usr/bin/bash
    set -euo pipefail
    credentials=$(kubectl exec -n "${airflow_model_name}" "${pod_name}" -c airflow-api-server -- \
        cat /opt/airflow/simple_auth_manager_passwords.json.generated)
    username=$(echo "${credentials}" | jq -er 'to_entries[0].key')
    password=$(echo "${credentials}" | jq -er 'to_entries[0].value')
    curl -sf -X POST "${api_url}/auth/token" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${username}\", \"password\": \"${password}\"}" | jq -er '.access_token'

[private]
wait-for-airflow-process-ready model_name pod_name="airflow-api-server-0":
    #!/usr/bin/bash
    set -euo pipefail
    echo "Waiting for ${pod_name} to finish initializing..."
    for _ in $(seq 1 60); do
        kubectl exec -n "${model_name}" "${pod_name}" -c airflow-api-server -- \
            test -f /opt/airflow/simple_auth_manager_passwords.json.generated 2>/dev/null && break
        sleep 5
    done

[private]
wait-for-api-health api_url="http://localhost:8080":
    #!/usr/bin/bash
    set -euo pipefail
    for _ in $(seq 1 30); do
        curl -sf --max-time 2 "${api_url}/api/v2/monitor/health" > /dev/null 2>&1 && break
        sleep 2
    done

# Generic poller: retries ${command} until it succeeds or times out, reporting a clear error on timeout.
[private]
poll-until description command timeout_seconds="300" interval_seconds="5":
    #!/usr/bin/bash
    set -euo pipefail
    elapsed=0
    echo "Waiting for: ${description}"
    until eval "${command}" > /dev/null 2>&1; do
        if [ "${elapsed}" -ge "${timeout_seconds}" ]; then
            echo "ERROR: timed out after ${elapsed}s waiting for: ${description}" >&2
            exit 1
        fi
        sleep "${interval_seconds}"
        elapsed=$((elapsed + interval_seconds))
    done
    echo "Ready: ${description}"


# Starts a kubectl port-forward to ${pod_name} if one isn't already running (tracked via ${pid_file}); idempotent across repeated calls
[private]
ensure-port-forward model_name pod_name pid_file port="8080":
    #!/usr/bin/bash
    set -euo pipefail
    if [ -f "${pid_file}" ] && kill -0 "$(cat ${pid_file})" 2>/dev/null; then
        exit 0
    fi
    kubectl port-forward -n "${model_name}" "pod/${pod_name}" ${port}:${port} > /dev/null 2>&1 &
    echo $! > "${pid_file}"
    sleep 2

# Copies the local test DAG into the dag-processor and scheduler pods (local DAG bundle has no shared storage - each pod needs its own copy).
[private]
copy-local-dag model_name dag_file="tests/dags/sample_dag.py":
    #!/usr/bin/bash
    set -euxo pipefail
    dag_name=$(basename "${dag_file}")
    for pod_container in "airflow-dag-processor-0:airflow-dag-processor" "airflow-scheduler-0:airflow-scheduler"; do
        pod="${pod_container%%:*}"
        container="${pod_container##*:}"
        kubectl wait --for=condition=Ready "pod/${pod}" -n "${model_name}" --timeout=120s
        kubectl exec -n "${model_name}" "${pod}" -c "${container}" -- mkdir -p /opt/airflow/dags
        kubectl cp "${dag_file}" "${model_name}/${pod}:/opt/airflow/dags/${dag_name}" -c "${container}"
    done

# Fetches SimpleAuthManager credentials, generates an access token, and logs airflowctl in.
[private]
airflowctl-login model_name pod_name="airflow-api-server-0" api_url="http://localhost:8080":
    #!/usr/bin/bash
    set -euo pipefail
    token=$(just fetch-access-token ${model_name} ${pod_name} ${api_url})
    AIRFLOW_CLI_TOKEN="${token}" uv run airflowctl auth login --api-url "${api_url}" --env production --skip-keyring >&2
    echo "${token}"

# Deploys Charmed Airflow with the Kubernetes executor and waits for all units to become active.
[private]
k8s-executor-deploy model_name:
    just deploy-k8s-executor ${model_name}
    just wait-for-active ${model_name}

# Waits for the Airflow API server's process to finish initializing and for its health endpoint to respond, via a port-forward.
[private]
k8s-executor-wait-ready model_name pod_name="airflow-api-server-0" api_url="http://localhost:8080":
    just poll-until "Airflow process ready (${pod_name})" \
        "kubectl exec -n ${model_name} ${pod_name} -c airflow-api-server -- test -f /opt/airflow/simple_auth_manager_passwords.json.generated" \
        300 5
    just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-k8s-executor-pf.pid
    just poll-until "API health check" \
        "just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-k8s-executor-pf.pid && curl -sf --max-time 2 ${api_url}/api/v2/monitor/health" \
        60 2

# Waits for ${dag_id} to be synced and parsed via the git-integrator DAG bundle.
[private]
k8s-executor-wait-dag-parsed model_name pod_name="airflow-api-server-0" api_url="http://localhost:8080" dag_id="example_simplest_dag":
    just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-k8s-executor-pf.pid
    just poll-until "${dag_id} to be parsed" \
        "just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-k8s-executor-pf.pid && uv run airflowctl dags list --env production 2>/dev/null | grep '^\['  | jq -e '.[] | select(.dag_id == \"${dag_id}\")'" \
        300 10

# Waits for ${dag_id} to be synced and parsed via the local DAG bundle.
[private]
core-operations-wait-dag-parsed model_name pod_name="airflow-api-server-0" api_url="http://localhost:8080" dag_id="uat_print_message_dag":
    just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-core-operations-pf.pid
    just poll-until "${dag_id} to be parsed" \
        "just ensure-port-forward ${model_name} ${pod_name} /tmp/uats-core-operations-pf.pid && uv run airflowctl dags list --env production 2>/dev/null | grep '^\['  | jq -e '.[] | select(.dag_id == \"${dag_id}\")'" \
        400 10

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
    for model in $(juju models --format=json | jq -er '.models[]."short-name"'); do
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
        if IDENTITY_UUID=$(juju show-model ${identity_model_name} --format=json | jq -er ".\"${identity_model_name}\"[\"model-uuid\"]" 2>/dev/null); then
            EXTRA_VARS="-var identity_model_uuid=${IDENTITY_UUID}"
        fi
    fi

    if MODEL_UUID=$(juju show-model ${model_name} --format=json | jq -er ".\"${model_name}\"[\"model-uuid\"]" 2>/dev/null); then
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

# Execute the Core Operations UATs for the Airflow (local executor): connectivity, list DAGs, trigger a DAG run and wait for it to complete.
uats-core-operations airflow_model_name="airflow" dag_id="uat_print_message_dag":
    #!/usr/bin/bash
    set -euxo pipefail
    pid_file="/tmp/uats-core-operations-pf.pid"
    trap '
        ec=$?
        [ -f "${pid_file}" ] && kill "$(cat ${pid_file})" 2>/dev/null || true
        if [ "${ec}" -ne 0 ]; then just destroy ${airflow_model_name} || true; fi
    ' EXIT

    # Installs airflowctl (pinned in uv.lock via the uats-core group)
    uv sync --active --group uats-core
    pod_name="airflow-api-server-0"
    api_url="http://localhost:8080"

    just deploy ${airflow_model_name}
    just wait-for-active ${airflow_model_name}

    just wait-for-airflow-process-ready ${airflow_model_name} ${pod_name}
    just copy-local-dag ${airflow_model_name}

    just ensure-port-forward ${airflow_model_name} ${pod_name} ${pid_file}
    just wait-for-api-health ${api_url}

    # Fetch the credentials from the pod and use them to get an access token for the API
    set +x
    export AIRFLOW_CLI_TOKEN=$(just fetch-access-token ${airflow_model_name} ${pod_name} ${api_url})
    set -x

    just core-operations-wait-dag-parsed ${airflow_model_name} ${pod_name} ${api_url} ${dag_id}

    uv run airflowctl dags unpause ${dag_id} > /dev/null 2>&1 || true
    if ! uv run airflowctl dags list --env production 2>/dev/null | grep '^\[' | jq -e --arg id "${dag_id}" '.[] | select(.dag_id == $id) | .is_paused == "False"' > /dev/null; then
        echo "ERROR: ${dag_id} is still paused after unpause attempt" >&2
        exit 1
    fi

    goss -g tests/goss/goss.yaml validate

# Orchestrates the Kubernetes Executor UAT: trigger a DAG run that executes in a Kubernetes Pod and wait for it to complete.
uats-kubernetes-executor airflow_model_name="airflow" pod_name="airflow-api-server-0" api_url="http://localhost:8080" dag_id="example_simplest_dag":
    #!/usr/bin/bash
    set -euxo pipefail
    pid_file="/tmp/uats-k8s-executor-pf.pid"
    trap '
        ec=$?
        [ -f "${pid_file}" ] && kill "$(cat ${pid_file})" 2>/dev/null || true
        if [ "${ec}" -ne 0 ]; then just destroy ${airflow_model_name} || true; fi
    ' EXIT

    uv sync --active --group uats-core

    just k8s-executor-deploy ${airflow_model_name}
    just k8s-executor-wait-ready ${airflow_model_name} ${pod_name} ${api_url}

    set +x
    export AIRFLOW_CLI_TOKEN=$(just airflowctl-login ${airflow_model_name} ${pod_name} ${api_url})
    set -x

    just k8s-executor-wait-dag-parsed ${airflow_model_name} ${pod_name} ${api_url} ${dag_id}

    uv run airflowctl dags unpause ${dag_id} > /dev/null 2>&1 || true
    if ! uv run airflowctl dags list --env production 2>/dev/null | grep '^\[' | jq -e --arg id "${dag_id}" '.[] | select(.dag_id == $id) | .is_paused == "False"' > /dev/null; then
        echo "ERROR: ${dag_id} is still paused after unpause attempt" >&2
        exit 1
    fi

    goss -g tests/goss/goss-kubernetes-executor.yaml validate

#!/usr/bin/env bash
# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.
#
# Generates a fernet key, stores it as a Juju secret,
# grants it to the airflow-coordinator charm, and configures it.

set -euo pipefail

SECRET_NAME="fernet-key-secret"
APP="airflow-coordinator"

# Check if secret already exists
if juju show-secret "$SECRET_NAME" 2>/dev/null; then
    SECRET_ID="secret:$(juju show-secret "$SECRET_NAME" --format=json 2>/dev/null | jq -r 'keys[0]')"
    echo "Secret already exists: $SECRET_ID"
else
    FERNET_KEY=$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')
    SECRET_ID=$(juju add-secret "$SECRET_NAME" fernet-key="$FERNET_KEY")
    juju grant-secret "$SECRET_ID" "$APP"
    echo "Created new secret: $SECRET_ID"
fi

juju config "$APP" fernet_key_secret="$SECRET_ID"
echo "Configured $APP with fernet key secret $SECRET_ID"

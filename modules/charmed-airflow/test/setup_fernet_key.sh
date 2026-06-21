#!/usr/bin/env bash
# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.
#
# Generates a fernet key, stores it as a Juju secret,
# grants it to the airflow-coordinator charm, and configures it.

set -euo pipefail

SECRET_NAME="fernet-key-secret"
APP="airflow-coordinator"

FERNET_KEY=$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')

SECRET_ID=$(juju add-secret "$SECRET_NAME" fernet-key="$FERNET_KEY")

juju grant-secret "$SECRET_ID" "$APP"

juju config "$APP" fernet_key_secret="$SECRET_ID"

echo "Configured $APP with fernet key secret $SECRET_ID"

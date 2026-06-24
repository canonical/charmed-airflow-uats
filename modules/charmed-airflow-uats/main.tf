# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

# Generate a cryptographically secure fernet key (32 random bytes)
resource "random_bytes" "fernet_key" {
  length = 32
}

# Create the Juju secret storing the fernet key
# Fernet requires URL-safe base64 (- and _ instead of + and /, no padding)
resource "juju_secret" "fernet_key" {
  model_uuid = var.model_uuid
  name       = "fernet-key-secret"
  value = {
    fernet-key = replace(replace(replace(
      random_bytes.fernet_key.base64,
      "+", "-"), "/", "_"), "=", "")
  }
}

# Deploy Charmed Airflow, passing the secret URI into coordinator config
module "charmed_airflow" {
  source = "git::https://github.com/canonical/charmed-airflow-solutions//modules/charmed-airflow?ref=track/3.1"
  model_uuid            = var.model_uuid
  postgresql            = var.postgresql
  pgbouncer             = var.pgbouncer
  airflow_api_server    = var.airflow_api_server
  airflow_scheduler     = var.airflow_scheduler
  airflow_triggerer     = var.airflow_triggerer
  airflow_dag_processor = var.airflow_dag_processor
  airflow_coordinator = merge(var.airflow_coordinator, {
    config = merge(var.airflow_coordinator.config, {
      fernet_key_secret = juju_secret.fernet_key.secret_uri
    })
  })

  depends_on = [juju_secret.fernet_key]
}

# Grant the secret to the coordinator AFTER it's deployed
resource "juju_access_secret" "fernet_key" {
  model_uuid   = var.model_uuid
  secret_id    = juju_secret.fernet_key.secret_id
  applications = [module.charmed_airflow.applications.airflow.coordinator.application.name]

  depends_on = [module.charmed_airflow]
}
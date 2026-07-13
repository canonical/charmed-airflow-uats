# Copyright 2026 Canonical Ltd.
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

  model_uuid = var.model_uuid
  executor                    = var.executor
  airflow_kubernetes_executor = var.airflow_kubernetes_executor

  postgresql = {
    units = 1
    profile = "testing"
  }

  airflow_coordinator = {
    config = {
      fernet_key_secret = juju_secret.fernet_key.secret_uri
    }
  }

}

# Grant the secret to the coordinator AFTER it's deployed
resource "juju_access_secret" "fernet_key" {
  model_uuid   = var.model_uuid
  secret_id    = juju_secret.fernet_key.secret_id
  applications = [module.charmed_airflow.applications.airflow.coordinator.application.name]

  depends_on = [module.charmed_airflow]
}

# Deploy PostgreSQL in the identity model for use by hydra and kratos
module "postgresql" {
  source = "github.com/canonical/postgresql-k8s-operator//terraform?ref=rev935"

  count      = var.identity_model_uuid != "" ? 1 : 0

  model_uuid = var.identity_model_uuid
  app_name   = "identity-postgresql"
  units   = 1
  channel = "14/stable"

  config  = {
    profile = "testing"
  }
}

# Deploy self signed certificates provider for use by Traefik in identity model
module "certificates" {
  source = "github.com/canonical/self-signed-certificates-operator//terraform?ref=rev443"

  count      = var.identity_model_uuid != "" ? 1 : 0

  model_uuid = var.identity_model_uuid
  app_name   = "self-signed-certificates"

  units   = 1
  channel = "1/stable"
}

# Deploy Traefik in the identity model
module "traefik" {
  source = "github.com/canonical/traefik-k8s-operator//terraform?ref=traefik-k8s-rev376"

  count      = var.identity_model_uuid != "" ? 1 : 0

  model_uuid = var.identity_model_uuid
  app_name   = "traefik-public"
  channel = "latest/stable"
  base = "ubuntu@26.04"

  units   = 1

  depends_on = [module.certificates]
}

# Deploy the identity platform, pointing it at the local PostgreSQL offer
module "identity" {
  count  = var.identity_model_uuid != "" ? 1 : 0
  source = "git::https://github.com/canonical/iam-bundle-integration?ref=main"

  model                = var.identity_model_uuid
  postgresql_offer_url = juju_offer.identity_postgresql[0].url
  traefik_route_offer_url = juju_offer.identity_traefik[0].url

  depends_on = [juju_offer.identity_postgresql, juju_offer.identity_traefik]
}

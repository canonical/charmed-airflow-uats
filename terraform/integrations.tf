# Expose PostgreSQL as a cross-model offer so the IAM bundle module can consume it
resource "juju_offer" "identity_postgresql" {
  count            = var.identity_model_uuid != "" ? 1 : 0
  name             = "postgresql-offer"
  application_name = module.postgresql[0].app_name
  endpoints        = [module.postgresql[0].provides.database]
  model_uuid       = var.identity_model_uuid
}

# Expose Traefik as a cross-model offer so the IAM bundle module can consume it
resource "juju_offer" "identity_traefik" {
  count            = var.identity_model_uuid != "" ? 1 : 0
  name             = "traefik-offer"
  application_name = module.traefik[0].app_name
  endpoints        = [module.traefik[0].endpoints.traefik_route]
  model_uuid       = var.identity_model_uuid
}

# Cross-model integration: connect Hydra OAuth offer to the airflow coordinator
resource "juju_integration" "coordinator_oauth" {
  count      = var.identity_model_uuid != "" ? 1 : 0
  model_uuid = var.model_uuid

  application {
    offer_url = module.identity[0].oauth_offer_url
  }

  application {
    name     = module.charmed_airflow.applications.airflow.coordinator.application.name
    endpoint = "oauth"
  }

  depends_on = [module.identity, module.charmed_airflow]
}

resource "juju_integration" "traefik_certs" {
  application {
    name     = module.traefik[0].app_name
    endpoint = "certificates"
  }

  application {
    name     = module.certificates[0].app_name
    endpoint = "certificates"
  }

  model_uuid = var.identity_model_uuid
}

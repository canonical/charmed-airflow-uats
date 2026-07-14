# Expose Identity OAuth as a cross-model offer so the Airflow module can consume it
resource "juju_offer" "identity_oauth" {
  count = var.identity_model_uuid != "" ? 1 : 0

  model_uuid = var.identity_model_uuid

  name             = "hydra-oauth"
  application_name = "hydra"

  endpoints = ["oauth"]
}

# Cross-model integration: connect Hydra OAuth offer to the airflow coordinator
resource "juju_integration" "coordinator_oauth" {
  count      = var.identity_model_uuid != "" ? 1 : 0
  model_uuid = var.airflow_model_uuid

  application {
    offer_url = one(juju_offer.identity_oauth[*]).url
  }

  application {
    name     = module.charmed_airflow.applications.airflow.coordinator.application.name
    endpoint = "oauth"
  }
}

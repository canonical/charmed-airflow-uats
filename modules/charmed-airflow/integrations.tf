resource "juju_integration" "postgresql_pgbouncer" {
  model_uuid = var.model_uuid

  application {
    name     = juju_application.pgbouncer.name
    endpoint = "backend-database"
  }

  application {
    name     = module.postgresql.application_name
    endpoint = "database"
  }
}

resource "juju_integration" "coordinator_to_pgbouncer" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "postgres"
  }

  application {
    name     = juju_application.pgbouncer.name
    endpoint = "database"
  }
}
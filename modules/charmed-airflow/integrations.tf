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

resource "juju_integration" "coordinator_to_api_server" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "airflow-coordinator"
  }

  application {
    name     = module.airflow_api_server.application.name
    endpoint = "airflow-coordinator"
  }
}

resource "juju_integration" "api_server_to_coordinator" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_api_server.application.name
    endpoint = "airflow-api-server"
  }

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "airflow-api-server"
  }
}

resource "juju_integration" "coordinator_to_scheduler" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "airflow-coordinator"
  }

  application {
    name     = module.airflow_scheduler.application.name
    endpoint = "airflow-coordinator"
  }
}

resource "juju_integration" "coordinator_to_triggerer" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "airflow-coordinator"
  }

  application {
    name     = module.airflow_triggerer.application.name
    endpoint = "airflow-coordinator"
  }
}

resource "juju_integration" "coordinator_to_dag_processor" {
  model_uuid = var.model_uuid

  application {
    name     = module.airflow_coordinator.application.name
    endpoint = "airflow-coordinator"
  }

  application {
    name     = module.airflow_dag_processor.application.name
    endpoint = "airflow-coordinator"
  }
}
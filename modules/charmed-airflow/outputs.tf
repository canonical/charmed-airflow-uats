
output "applications" {
  description = "Names and details of the deployed applications."
  value = {
    postgresql = {
      application_name = module.postgresql.application_name
      provides         = module.postgresql.provides
      requires         = module.postgresql.requires
    }
    pgbouncer          = juju_application.pgbouncer
    airflow_coordinator = {
      application = module.airflow_coordinator.application
      provides    = module.airflow_coordinator.provides
      requires    = module.airflow_coordinator.requires
    }
    airflow_api_server = {
      application = module.airflow_api_server.application
      provides    = module.airflow_api_server.provides
      requires    = module.airflow_api_server.requires
    }
    airflow_scheduler = {
      application = module.airflow_scheduler.application
      requires    = module.airflow_scheduler.requires
    }
    airflow_triggerer = {
      application = module.airflow_triggerer.application
      requires    = module.airflow_triggerer.requires
    }
    airflow_dag_processor = {
      application = module.airflow_dag_processor.application
      requires    = module.airflow_dag_processor.requires
    }
  }
}
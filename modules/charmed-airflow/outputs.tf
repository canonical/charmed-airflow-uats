
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
  }
}
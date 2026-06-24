variable "model_uuid" {
  description = "UUID of the juju model to deploy to."
  type        = string
}

variable "postgresql" {
  description = "Inputs for postgresql-k8s charm module."
  type = object({
    app_name           = optional(string, "postgresql")
    channel            = optional(string, "14/stable")
    base               = optional(string, "ubuntu@22.04")
    units              = optional(number, 3)
    profile            = optional(string, "production")
    config             = optional(map(string), {})
    revision           = optional(number, null)
    storage_directives = optional(map(string), {})
  })
  default = {}
}

variable "pgbouncer" {
  description = "Inputs for pgbouncer-k8s charm."
  type = object({
    app_name = optional(string, "pgbouncer")
    channel  = optional(string, "1/stable")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "airflow_coordinator" {
  description = "Inputs for airflow-coordinator-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-coordinator")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "airflow_api_server" {
  description = "Inputs for airflow-api-server-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-api-server")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "airflow_scheduler" {
  description = "Inputs for airflow-scheduler-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-scheduler")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "airflow_triggerer" {
  description = "Inputs for airflow-triggerer-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-triggerer")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "airflow_dag_processor" {
  description = "Inputs for airflow-dag-processor-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-dag-processor")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}
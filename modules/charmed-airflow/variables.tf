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
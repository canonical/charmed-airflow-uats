# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

variable "airflow_model_uuid" {
  description = "UUID of the Juju model to deploy Charmed Airflow into."
  type        = string
}

variable "identity_model_uuid" {
  description = "UUID of the Juju model hosting the identity platform. When empty, Identity platform is not deployed"
  type        = string
  default     = ""
}

variable "executor" {
  description = "The executor type to deploy. When null, LocalExecutor is used. Supported values: \"kubernetes\"."
  type        = string
  default     = null
  validation {
    condition     = var.executor == null || contains(["kubernetes"], var.executor)
    error_message = "Unsupported executor type. Supported values: null, \"kubernetes\"."
  }
}

variable "airflow_kubernetes_executor" {
  description = "Inputs for airflow-kubernetes-executor-k8s charm module."
  type = object({
    app_name = optional(string, "airflow-kubernetes-executor")
    channel  = optional(string, "3.1/edge")
    units    = optional(number, 1)
    config   = optional(map(string), {})
    revision = optional(number, null)
  })
  default = {}
}

variable "deploy_git_integrator" {
  description = "Whether to deploy git-integrator, related to the coordinator, for loading DAGs from a git repository."
  type        = bool
  default     = false
}

variable "git_integrator" {
  description = "Inputs for git-integrator charm module. Defaults point at apache/airflow example DAGs. Only deployed when deploy_git_integrator is true."
  type = object({
    app_name = optional(string, "git-integrator")
    channel  = optional(string, "1.0/edge")
    units    = optional(number, 1)
    config = optional(map(string), {
      repository_url = "https://github.com/apache/airflow"
      path           = "airflow-core/src/airflow/example_dags"
      tracking_ref   = "v3-1-stable"
    })
    revision = optional(number, null)
  })
  default = {}
}

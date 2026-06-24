# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.

variable "model_uuid" {
  description = "UUID of the Juju model to deploy Charmed Airflow into."
  type        = string
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

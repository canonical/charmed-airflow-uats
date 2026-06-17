module "postgresql" {
  # rev742 is a revision for postgresql-k8s 16/edge.
  source             = "git::https://github.com/canonical/postgresql-k8s-operator//terraform?ref=rev742"
  juju_model         = var.model_uuid
  app_name           = var.postgresql.app_name
  channel            = var.postgresql.channel
  base               = var.postgresql.base
  units              = var.postgresql.units
  storage_directives = var.postgresql.storage_directives
  config = merge(
    var.postgresql.config,
    { profile = var.postgresql.profile }
  )
  revision = var.postgresql.revision
}

resource "juju_application" "pgbouncer" {
  name       = var.pgbouncer.app_name
  model_uuid = var.model_uuid
  trust      = true
  units      = var.pgbouncer.units
  config     = var.pgbouncer.config
  charm {
    name     = "pgbouncer-k8s"
    channel  = var.pgbouncer.channel
    revision = var.pgbouncer.revision
  }
}
# model_uuid is injected at runtime by the justfile.
executor = "kubernetes"
deploy_git_integrator = true
airflow_kubernetes_executor = {
  config = {
    base_image = "ghcr.io/dnplas/airflow-worker:3.1.8-impersonation"
    namespace  = "airflow-executor-workers"
  }
}
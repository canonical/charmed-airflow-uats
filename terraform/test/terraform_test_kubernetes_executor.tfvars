# model_uuid is injected at runtime by the justfile.
executor              = "kubernetes"
deploy_git_integrator = true
airflow_kubernetes_executor = {
  config = {
    base_image = "ubuntu/airflow:3.1-24.04_edge"
    namespace  = "airflow-executor-workers"
  }
}
git_integrator = {
  config = {
    repository_url = "https://github.com/apache/airflow"
    path           = "airflow-core/src/airflow/example_dags"
    tracking_ref   = "v3-1-stable"
  }
}

# model_uuid is injected at runtime by the justfile.
executor = "kubernetes"
airflow_kubernetes_executor = {
  config = {
    base_image = "ubuntu/airflow:3.1-24.04_edge"
    namespace  = "airflow-executor-workers"
  }
}

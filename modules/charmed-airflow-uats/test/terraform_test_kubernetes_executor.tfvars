postgresql = {
  profile = "testing"
}
executor = "kubernetes"
airflow_kubernetes_executor = {
  config = {
    base_image = "ubuntu/airflow:3.1-24.04_edge"
    namespace  = "airflow-executor-workers"
  }
}

provider "twc" {
  token = var.timeweb_token
}

resource "twc_k8s_cluster" "main" {
  name           = var.cluster_name
  project_id     = var.project_id
  network_id     = var.network_id
  network_driver = var.network_driver
  preset_id      = var.cluster_preset_id
  version        = var.k8s_version
}

resource "twc_k8s_node_group" "workers" {
  cluster_id     = twc_k8s_cluster.main.id
  name           = "${var.cluster_name}-workers"
  preset_id      = var.node_preset_id
  node_count     = var.node_count
  is_autoscaling = var.autoscaling
}

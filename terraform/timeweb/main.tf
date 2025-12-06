terraform {
  required_providers {
    twc = {
      source = "tf.timeweb.cloud/timeweb-cloud/timeweb-cloud"
    }
  }
}

provider "twc" {
  token = var.timeweb_token
}

module "k8s" {
  source = "git::https://github.com/justgithubaccount/infra-cluster.git//modules/timeweb-k8s?ref=main"

  cluster_name      = var.cluster_name
  project_id        = var.project_id
  network_id        = var.network_id
  cluster_preset_id = var.cluster_preset_id
  node_preset_id    = var.node_preset_id
  node_count        = var.node_count
  k8s_version       = var.k8s_version
  network_driver    = var.network_driver
  autoscaling       = var.autoscaling
}

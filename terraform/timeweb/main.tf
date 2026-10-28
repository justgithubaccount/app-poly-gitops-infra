provider "twc" {
  token = var.timeweb_token
}

data "twc_k8s_preset" "master" {
  cpu      = var.master_cpu
  location = var.location
  type     = "master"
}

data "twc_k8s_preset" "worker" {
  cpu      = var.worker_cpu
  location = var.location
  type     = "worker"
}

locals {
  estimated_monthly_rub = data.twc_k8s_preset.master.price + (data.twc_k8s_preset.worker.price * var.node_count)
  estimated_run_rub     = local.estimated_monthly_rub / 720 * (var.max_runtime_minutes / 60)
}

resource "terraform_data" "cost_guard" {
  input = local.estimated_run_rub

  lifecycle {
    precondition {
      condition     = local.estimated_run_rub <= var.max_cost_rub
      error_message = "Estimated smoke-run cost exceeds max_cost_rub."
    }
  }
}

module "k8s" {
  source = "git::https://github.com/justgithubaccount/infra-cluster.git//modules/timeweb-k8s?ref=3ed281361a2f03fd3dccc5776369ad5445b1acb9"

  cluster_name      = var.cluster_name
  project_id        = var.project_id
  network_id        = var.network_id
  cluster_preset_id = tonumber(data.twc_k8s_preset.master.id)
  node_preset_id    = tonumber(data.twc_k8s_preset.worker.id)
  node_count        = var.node_count
  k8s_version       = var.k8s_version
  network_driver    = var.network_driver
  autoscaling       = var.autoscaling

  depends_on = [terraform_data.cost_guard]
}

output "cluster_id" {
  description = "Kubernetes cluster ID"
  value       = module.k8s.cluster_id
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = module.k8s.cluster_name
}

output "node_group_id" {
  description = "Node group ID"
  value       = module.k8s.node_group_id
}

output "kubeconfig" {
  description = "Kubernetes cluster kubeconfig"
  value       = module.k8s.kubeconfig
  sensitive   = true
}

output "estimated_run_cost_rub" {
  description = "Estimated infrastructure cost for max_runtime_minutes"
  value       = local.estimated_run_rub
}

output "selected_presets" {
  description = "Preset IDs and monthly prices selected by the provider"
  value = {
    master = {
      id                = data.twc_k8s_preset.master.id
      monthly_price_rub = data.twc_k8s_preset.master.price
    }
    worker = {
      id                = data.twc_k8s_preset.worker.id
      monthly_price_rub = data.twc_k8s_preset.worker.price
    }
  }
}

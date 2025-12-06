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

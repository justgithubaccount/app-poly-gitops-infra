output "cluster_id" {
  description = "Kubernetes cluster ID"
  value       = twc_k8s_cluster.main.id
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = twc_k8s_cluster.main.name
}

output "node_group_id" {
  description = "Node group ID"
  value       = twc_k8s_node_group.workers.id
}

output "kubeconfig" {
  description = "Kubernetes cluster kubeconfig"
  value       = twc_k8s_cluster.main.kubeconfig
  sensitive   = true
}

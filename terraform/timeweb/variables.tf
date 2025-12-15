variable "timeweb_token" {
  description = "Timeweb Cloud API token"
  type        = string
  sensitive   = true
}

variable "project_id" {
  description = "Timeweb project ID"
  type        = number
  default     = 1115913
}

variable "network_id" {
  description = "Timeweb network ID"
  type        = string
  default     = "network-114cf1a7c6e9419bb665f0458621c83d"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "gitops-cluster"
}

variable "cluster_preset_id" {
  description = "Cluster preset ID (determines cluster resources)"
  type        = number
  default     = 403
}

variable "node_preset_id" {
  description = "Node preset ID (determines node resources)"
  type        = number
  default     = 445
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.34.2+k0s.0"
}

variable "network_driver" {
  description = "Network driver (calico, flannel, cilium)"
  type        = string
  default     = "calico"
}

variable "autoscaling" {
  description = "Enable node autoscaling"
  type        = bool
  default     = false
}

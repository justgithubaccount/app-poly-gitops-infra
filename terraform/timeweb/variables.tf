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
  default     = "network-559c3f2944a145deb01b610c27f1fa9a"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "gitops-cluster"
}

variable "cluster_preset_id" {
  description = "Cluster preset ID (determines cluster resources)"
  type        = number
  default     = 1675
}

variable "node_preset_id" {
  description = "Node preset ID (determines node resources)"
  type        = number
  default     = 1683
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

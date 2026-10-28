variable "timeweb_token" {
  description = "Timeweb Cloud API token"
  type        = string
  sensitive   = true
}

variable "project_id" {
  description = "Optional Timeweb project ID; null uses the account default"
  type        = number
  default     = null
}

variable "network_id" {
  description = "Optional Timeweb VPC ID"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "gitops-cluster"
}

variable "location" {
  description = "Timeweb location used to select Kubernetes presets"
  type        = string
  default     = "ru-1"
}

variable "master_cpu" {
  description = "CPU count used to select the control-plane preset"
  type        = number
  default     = 2
}

variable "worker_cpu" {
  description = "CPU count used to select the worker preset"
  type        = number
  default     = 2
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "The disposable smoke environment is limited to one worker node."
  }
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.34.2+k0s.0"
}

variable "network_driver" {
  description = "Network driver (calico, flannel, cilium)"
  type        = string
  default     = "flannel"
}

variable "autoscaling" {
  description = "Enable node autoscaling"
  type        = bool
  default     = false
}

variable "max_runtime_minutes" {
  description = "Runtime used for the pre-apply cost estimate"
  type        = number
  default     = 120
}

variable "max_cost_rub" {
  description = "Maximum estimated infrastructure cost for a smoke run"
  type        = number
  default     = 80
}

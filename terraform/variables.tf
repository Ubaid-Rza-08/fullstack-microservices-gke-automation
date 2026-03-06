# ══════════════════════════════════════════════════════════════════════════════
#  Variables — set values in terraform.tfvars (never commit that file)
# ══════════════════════════════════════════════════════════════════════════════

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the GKE cluster"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name for the GKE cluster and related resources"
  type        = string
  default     = "tax-calculator"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "subnet_cidr" {
  description = "Primary CIDR for the subnet (nodes)"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR for Kubernetes pods"
  type        = string
  default     = "10.48.0.0/14"
}

variable "services_cidr" {
  description = "Secondary CIDR for Kubernetes services"
  type        = string
  default     = "10.52.0.0/20"
}

variable "master_cidr" {
  description = "CIDR for GKE control plane (must be /28)"
  type        = string
  default     = "172.16.0.0/28"
}

# ── Node Pool ─────────────────────────────────────────────────────────────────

variable "machine_type" {
  description = "GCE machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}

variable "initial_nodes" {
  description = "Initial node count per zone"
  type        = number
  default     = 1
}

variable "min_nodes" {
  description = "Minimum nodes for autoscaling"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum nodes for autoscaling"
  type        = number
  default     = 4
}

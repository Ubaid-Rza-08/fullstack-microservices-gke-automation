# ══════════════════════════════════════════════════════════════════════════════
#  Outputs — printed after terraform apply
# ══════════════════════════════════════════════════════════════════════════════

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_zone" {
  description = "GKE cluster zone"
  value       = google_container_cluster.primary.location
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "kubectl_command" {
  description = "Run this to configure kubectl after apply"
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "gke_service_account" {
  description = "Service account used by GKE nodes"
  value       = google_service_account.gke_sa.email
}

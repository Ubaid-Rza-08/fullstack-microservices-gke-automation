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

output "kubectl_command" {
  description = "Run this to configure kubectl after apply"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "github_actions_sa_email" {
  description = "GitHub Actions service account email"
  value       = google_service_account.github_actions_sa.email
}

output "github_actions_key_file" {
  description = "Path to the JSON key file — copy contents → GitHub Secret GCP_SA_KEY"
  value       = "${path.module}/github-actions-key.json"
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT

    ✅ Terraform apply complete! Now do:

    1. Configure kubectl:
       gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project_id}

    2. Copy GCP_SA_KEY → GitHub Secret:
       cat ${path.module}/github-actions-key.json
       → copy entire JSON → GitHub repo → Settings → Secrets → GCP_SA_KEY

    3. Add remaining GitHub Secrets:
       GCP_CLUSTER_NAME = ${google_container_cluster.primary.name}
       GCP_REGION       = ${google_container_cluster.primary.location}
       GCP_PROJECT_ID   = ${var.project_id}

    4. Install nginx ingress controller:
       kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

    5. Push to main branch → pipeline triggers automatically
  EOT
}

# ══════════════════════════════════════════════════════════════════════════════
#  Terraform — Production GKE Infrastructure
#  Resources: VPC, Subnets, GKE Cluster, Node Pool (autoscaling),
#             GitHub Actions Service Account + Key
# ══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Enable required GCP APIs ──────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ═══════════════════════════════════════════════════════════════════════════════
#  GITHUB ACTIONS — Service Account + Roles + Key
# ═══════════════════════════════════════════════════════════════════════════════

# ── Create Service Account ────────────────────────────────────────────────────
resource "google_service_account" "github_actions_sa" {
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions SA"
  description  = "Used by GitHub Actions CI/CD to deploy to GKE"

  depends_on = [google_project_service.apis]
}

# ── Grant Roles ───────────────────────────────────────────────────────────────
resource "google_project_iam_member" "github_actions_roles" {
  for_each = toset([
    "roles/container.developer",      # deploy to GKE
    "roles/container.clusterViewer",  # get cluster credentials
    "roles/iam.serviceAccountUser",   # act as service account
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# ── Create JSON Key ───────────────────────────────────────────────────────────
resource "google_service_account_key" "github_actions_key" {
  service_account_id = google_service_account.github_actions_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"

  depends_on = [google_project_iam_member.github_actions_roles]
}

# ── Save key to local file (copy content → GitHub Secret GCP_SA_KEY) ─────────
resource "local_file" "github_actions_key_file" {
  content  = base64decode(google_service_account_key.github_actions_key.private_key)
  filename = "${path.module}/github-actions-key.json"

  # ⚠️ This file is gitignored — never commit it
}

# ═══════════════════════════════════════════════════════════════════════════════
#  VPC NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

# ── Subnet with secondary ranges for Pods & Services ─────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

# ── Cloud Router + NAT ────────────────────────────────────────────────────────
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  GKE NODE SERVICE ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_service_account" "gke_sa" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "GKE Node Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  GKE CLUSTER
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  deletion_protection = false

  depends_on = [google_project_service.apis]
}

# ── Node Pool with Autoscaling ────────────────────────────────────────────────
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  initial_node_count = var.initial_nodes

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      env     = "production"
      project = var.cluster_name
    }

    tags = ["gke-node", var.cluster_name]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# ── Firewall ──────────────────────────────────────────────────────────────────
resource "google_compute_firewall" "gke_master_webhook" {
  name    = "${var.cluster_name}-master-webhook"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "15017"]
  }

  source_ranges = [var.master_cidr]
  target_tags   = ["gke-node"]
}

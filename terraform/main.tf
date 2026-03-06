# ══════════════════════════════════════════════════════════════════════════════
#  Terraform — Production GKE Infrastructure
#  Resources: VPC, Subnets, GKE Cluster, Node Pool (autoscaling)
# ══════════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # ── Remote state on GCS (recommended for teams) ───────────────────────────
  # Uncomment and set your bucket name after running:
  #   gsutil mb gs://YOUR_PROJECT_ID-tf-state
  #
  # backend "gcs" {
  #   bucket = "YOUR_PROJECT_ID-tf-state"
  #   prefix = "tax-calculator/state"
  # }
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
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── VPC Network ───────────────────────────────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false   # custom subnets only

  depends_on = [google_project_service.apis]
}

# ── Subnet with secondary ranges for Pods & Services ─────────────────────────
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  # Secondary ranges required for GKE VPC-native networking
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true   # allows private nodes to reach GCP APIs
}

# ── Cloud Router + NAT (lets private nodes pull Docker images) ────────────────
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

# ── GKE Service Account ───────────────────────────────────────────────────────
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

# ── GKE Cluster ───────────────────────────────────────────────────────────────
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  # Remove default node pool — we manage our own below
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # VPC-native (alias IP) — required for proper pod networking
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false   # keep public endpoint for kubectl access
    master_ipv4_cidr_block  = var.master_cidr
  }

  # Allow kubectl from anywhere (restrict to your IP in production)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  # Workload Identity — secure way for pods to access GCP APIs
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  deletion_protection = false   # set true for real production

  depends_on = [google_project_service.apis]
}

# ── Node Pool with Autoscaling ────────────────────────────────────────────────
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name

  # Autoscaling config
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  initial_node_count = var.initial_nodes

  # Auto repair & upgrade
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

    # Workload Identity on nodes
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

# ── Firewall: allow GKE master to reach nodes ─────────────────────────────────
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

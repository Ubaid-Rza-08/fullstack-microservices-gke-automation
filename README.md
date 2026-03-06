# 🧾 Tax Calculator — Fullstack Microservices on GCP GKE

> A production-ready fullstack microservices project built with **Spring Boot**, **React/Vite**, **Docker**, **Terraform**, and a complete **GitHub Actions CI/CD pipeline** deploying to **Google Kubernetes Engine (GKE)**.

![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)
![GKE](https://img.shields.io/badge/Deploy-GKE-4285F4?logo=google-cloud&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Hub-2496ED?logo=docker&logoColor=white)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)
![Java](https://img.shields.io/badge/Java-21-ED8B00?logo=openjdk&logoColor=white)
![React](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=black)

---

## 🏆 What This Project Demonstrates

- **Microservices architecture** — 2 Spring Boot services communicating internally
- **React/Vite frontend** served through Nginx reverse proxy
- **Docker Compose** for local staging environment
- **Terraform IaC** — VPC, private GKE cluster, NAT, autoscaling node pool, service accounts
- **GitHub Actions CI/CD** — parallel builds, Docker push, GKE deploy on every `git push`
- **Kubernetes Nginx Ingress** — single entry point routing traffic to services

---

## 📐 Architecture

```
                          Internet
                              │
                              ▼
                  ┌───────────────────────┐
                  │  Nginx Ingress (GKE)  │
                  │   External IP : 80    │
                  └───────────────────────┘
                         │          │
               /api/(.*)            /(.*)
                    │                    │
                    ▼                    ▼
          ┌──────────────────┐   ┌──────────────┐
          │   service-a      │   │   frontend   │
          │  (Price Calc)    │   │  (React/Vite)│
          │  ClusterIP:80    │   │  ClusterIP:80│
          │  → container:3000│   │  → nginx:80  │
          └──────────────────┘   └──────────────┘
                    │
                    ▼
          ┌──────────────────┐
          │   service-b      │
          │  (Tax Calc)      │
          │  ClusterIP:4000  │
          │  (internal only) │
          └──────────────────┘
```

### Service Responsibilities

| Service | Role | Port | Access |
|---|---|---|---|
| `service-b` | Returns tax rate by country | 4000 | Internal only (ClusterIP) |
| `service-a` | Calculates price + tax, calls service-b | 3000 | Via Ingress `/api/*` |
| `frontend` | React UI, proxies API calls via nginx | 80 | Via Ingress `/(.*)` |

---

## 📁 Project Structure

```
GCP/
├── .github/
│   └── workflows/
│       └── ci-cd.yml                        ← GitHub Actions pipeline
│
├── docker/app2-tax-calculator/
│   ├── spring/
│   │   ├── service-a/                       ← Price Service (Java 21 + Spring Boot)
│   │   │   ├── src/main/java/...
│   │   │   ├── pom.xml
│   │   │   └── Dockerfile
│   │   └── service-b/                       ← Tax Service (Java 21 + Spring Boot)
│   │       ├── src/main/java/...
│   │       ├── pom.xml
│   │       └── Dockerfile
│   └── tax-calculator-frontend/             ← React 19 + Vite 7 + Tailwind
│       ├── src/
│       ├── nginx.conf                       ← Nginx reverse proxy config
│       ├── package.json
│       └── Dockerfile
│
├── k8s/
│   ├── service-a.yaml                       ← Deployment + ClusterIP
│   ├── service-b.yaml                       ← Deployment + ClusterIP
│   ├── frontend.yaml                        ← Deployment + ClusterIP
│   └── ingress.yaml                         ← Nginx Ingress routing rules
│
├── terraform/
│   ├── main.tf                              ← VPC, GKE, Node Pool, Service Accounts
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── .gitignore                           ← excludes *.tfvars, *.tfstate, key.json
│
├── docker-compose.yml                       ← Root-level compose for local staging
└── README.md
```

---

## 🚀 Running the Project

### Option 1 — Local Development (No Docker)

**Prerequisites:** Java 21, Maven 3.9+, Node 24

```powershell
# Terminal 1 — Tax Service (service-b)
cd docker/app2-tax-calculator/spring/service-b
mvn spring-boot:run

# Terminal 2 — Price Service (service-a)
cd docker/app2-tax-calculator/spring/service-a
$env:TAX_SERVICE_URL = "http://localhost:4000"
mvn spring-boot:run

# Terminal 3 — React Frontend
cd docker/app2-tax-calculator/tax-calculator-frontend
npm install
$env:VITE_API_URL = "http://localhost:3100"
npm run dev
```

| Service | URL |
|---|---|
| Frontend | http://localhost:5173 |
| service-a | http://localhost:3000 |
| service-b | http://localhost:4000 |

---

### Option 2 — Docker Compose (Staging)

**Prerequisites:** Docker Desktop

```powershell
# Build JARs first
cd docker/app2-tax-calculator/spring/service-a && mvn clean package -DskipTests
cd ../service-b && mvn clean package -DskipTests
cd ../../..

# Start all services
docker compose up --build

# Stop
docker compose down
```

| Service | URL |
|---|---|
| Frontend | http://localhost:5173 |
| service-a | http://localhost:3100 |
| service-b | http://localhost:3200 |

---

### Option 3 — GKE Production (Full CI/CD)

See [CI/CD Pipeline](#️-cicd-pipeline) and [GKE Deployment](#-gke-deployment) sections below.

---

## ⚙️ CI/CD Pipeline

**Trigger:** Push to `main` branch

```
git push origin main
        │
        ▼
┌───────────────────────────────────────────┐
│  Job 1: build-test (matrix: parallel)     │
│  ├── service-a: mvn clean verify          │
│  └── service-b: mvn clean verify          │
│  → uploads surefire test reports          │
└───────────────────────────────────────────┘
        │
        ├─────────────────────────────────────┐
        ▼                                     ▼
┌──────────────────────┐       ┌─────────────────────────┐
│  Job 2:              │       │  Job 3:                  │
│  docker-build-push   │       │  docker-build-push       │
│  (Spring services)   │       │  -frontend               │
│  ├── mvn package     │       │  ├── Docker build        │
│  ├── Docker build    │       │  │   (VITE_API_URL=/api) │
│  └── Push DockerHub  │       │  └── Push DockerHub      │
└──────────────────────┘       └─────────────────────────┘
        │                                     │
        └──────────────┬──────────────────────┘
                       ▼
        ┌──────────────────────────────────────┐
        │  Job 4: deploy-gcp-gke               │
        │  ├── Auth → GCP (SA key)             │
        │  ├── kubectl apply k8s/              │
        │  ├── rollout restart (pull :latest)  │
        │  ├── rollout status --timeout=120s   │
        │  └── kubectl get pods -o wide        │
        └──────────────────────────────────────┘
```

### Docker Images

| Image | DockerHub |
|---|---|
| Price Service | `ubaidrza/tax-service-a:latest` |
| Tax Service | `ubaidrza/tax-service-b:latest` |
| Frontend | `ubaidrza/tax-calculator-frontend:latest` |

---

## 🔐 GitHub Secrets

**Location:** Repo → Settings → Secrets and variables → Actions

| Secret | Value |
|---|---|
| `DOCKER_USERNAME` | `ubaidrza` |
| `DOCKER_PASSWORD` | Docker Hub Access Token |
| `GCP_SA_KEY` | Full JSON content of `terraform/github-actions-key.json` |
| `GCP_CLUSTER_NAME` | `tax-calculator` |
| `GCP_REGION` | `us-central1-a` |
| `GCP_PROJECT_ID` | `iccs-model` |

---

## 🌍 Terraform Infrastructure

### Resources Created by `terraform apply`

| Resource | Name | Details |
|---|---|---|
| VPC | `tax-calculator-vpc` | Custom, no auto subnets |
| Subnet | `tax-calculator-subnet` | `10.0.0.0/20`, pods: `10.48.0.0/14` |
| Cloud Router | `tax-calculator-router` | `us-central1` |
| Cloud NAT | `tax-calculator-nat` | Private nodes → internet |
| GKE Cluster | `tax-calculator` | Private nodes, VPC-native, Workload Identity |
| Node Pool | `tax-calculator-node-pool` | `e2-medium`, autoscale 1→4, auto-repair |
| GKE Node SA | `tax-calculator-sa` | Logging, monitoring, artifact registry |
| GitHub Actions SA | `github-actions-sa` | container.developer + clusterViewer |
| SA Key | `github-actions-key.json` | Saved locally (gitignored) |

### Deploy Infrastructure

```powershell
cd terraform

# First time setup
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars → set project_id = "iccs-model"

terraform init
terraform plan
terraform apply   # ~12 minutes
```

### After Apply — Configure kubectl

```powershell
gcloud container clusters get-credentials tax-calculator --zone us-central1-a --project iccs-model
```

### Destroy Infrastructure

```powershell
terraform destroy
```

---

## ☸️ GKE Deployment

### One-Time Setup — Install Nginx Ingress Controller

```bash
# Run in GCP Cloud Shell (console.cloud.google.com → >_ icon)
gcloud container clusters get-credentials tax-calculator --zone us-central1-a --project iccs-model

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# Wait for external IP (~2 minutes)
kubectl get svc -n ingress-nginx -w
```

### Get App URL

```bash
kubectl get ingress
# Copy ADDRESS → open http://ADDRESS in browser
```

### Kubernetes Manifests

| File | Resources | Port Mapping |
|---|---|---|
| `service-b.yaml` | Deployment + ClusterIP | 4000→4000 |
| `service-a.yaml` | Deployment + ClusterIP | 80→3000 |
| `frontend.yaml` | Deployment + ClusterIP | 80→80 |
| `ingress.yaml` | Nginx Ingress | `/api/(.*)` → service-a, `/(.*)` → frontend |

---

## 🛠️ Tech Stack

| Category | Technology | Version |
|---|---|---|
| Backend | Spring Boot | 4.0 |
| Language | Java | 21 |
| Build | Maven | 3.9+ |
| Frontend | React | 19 |
| Bundler | Vite | 7 |
| Styling | Tailwind CSS | 4 |
| Container | Docker + Nginx | latest |
| Orchestration | Kubernetes | GKE v1.34 |
| Infrastructure | Terraform | ≥1.5 |
| Cloud | GCP (GKE, VPC, NAT) | — |
| CI/CD | GitHub Actions | — |
| Registry | Docker Hub | — |
| Ingress | Nginx Ingress Controller | v1.10.1 |

---

## 📋 Useful kubectl Commands

```bash
# View all running pods
kubectl get pods -o wide

# Follow logs
kubectl logs -l app=service-a -f
kubectl logs -l app=service-b -f
kubectl logs -l app=frontend  -f

# Force redeploy (pull latest image)
kubectl rollout restart deployment/service-a
kubectl rollout restart deployment/service-b
kubectl rollout restart deployment/frontend

# Check rollout status
kubectl rollout status deployment/frontend --timeout=120s

# Describe a failing pod
kubectl describe pod <pod-name>

# Get ingress IP
kubectl get ingress

# Check ingress-nginx
kubectl get svc -n ingress-nginx
```

---

## 🧹 Cleanup

```bash
# Delete all Kubernetes resources
kubectl delete -f k8s/

# Delete nginx ingress controller
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# Destroy all GCP infrastructure
cd terraform
terraform destroy
```

---

## 👨‍💻 Author

**Mo. Ubaid Rza**

[![GitHub](https://img.shields.io/badge/GitHub-Ubaid--Rza--08-181717?logo=github)](https://github.com/Ubaid-Rza-08)
[![DockerHub](https://img.shields.io/badge/DockerHub-ubaidrza-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/u/ubaidrza)
[![Portfolio](https://img.shields.io/badge/Portfolio-Visit-00C7B7)](https://ubaid-rza-08.github.io/my-portfolio/)

> B.Tech Computer Science · Jabalpur Engineering College
> Java Developer · Spring Boot Microservices · Cloud Native · GKE · Terraform
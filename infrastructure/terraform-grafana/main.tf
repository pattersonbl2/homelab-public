# Grafana Configuration via Terraform
#
# This configures Grafana data sources, folders, and dashboards.
#
# Prerequisites:
#   1. Grafana running and accessible
#   2. Create a service account in Grafana with Admin role
#   3. Generate a service account token
#   4. Set the token in terraform.tfvars
#
# Usage:
#   cd infrastructure/terraform-grafana
#   terraform init
#   terraform plan
#   terraform apply

# ─────────────────────────────────────────────────────────────────────────────
# Data Sources (read-only - provisioned by kube-prometheus-stack Helm chart)
# ─────────────────────────────────────────────────────────────────────────────

data "grafana_data_source" "prometheus" {
  name = "Prometheus"
}

data "grafana_data_source" "loki" {
  name = "Loki"
}

data "grafana_data_source" "alertmanager" {
  name = "Alertmanager"
}

# ─────────────────────────────────────────────────────────────────────────────
# Folders
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_folder" "infrastructure" {
  title = "Infrastructure"
}

resource "grafana_folder" "k3s_cluster" {
  title = "K3s Cluster"
}

resource "grafana_folder" "docker_homelab1" {
  title = "Docker / homelab-1"
}

resource "grafana_folder" "applications" {
  title = "Applications"
}

resource "grafana_folder" "vps" {
  title = "VPS"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboards - Infrastructure (Proxmox, NVIDIA GPU, VyOS, Homelab Overview)
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_dashboard" "proxmox" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/proxmox.json")
}

resource "grafana_dashboard" "nvidia_gpu" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/nvidia-gpu.json")
}

resource "grafana_dashboard" "homelab_overview" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/homelab-overview.json")
}

resource "grafana_dashboard" "vyos_router" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("${path.module}/dashboards/vyos-router.json")
}

# node-exporter-full is provisioned by kube-prometheus-stack helm chart (gnetId 1860)
# Do not manage it here — Grafana marks it as read-only

# ─────────────────────────────────────────────────────────────────────────────
# Dashboards - K3s Cluster (Kubernetes, Longhorn, Hubble, Network)
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_dashboard" "kubernetes" {
  folder      = grafana_folder.k3s_cluster.id
  config_json = file("${path.module}/dashboards/kubernetes.json")
}

resource "grafana_dashboard" "longhorn" {
  folder      = grafana_folder.k3s_cluster.id
  config_json = file("${path.module}/dashboards/longhorn.json")
}

resource "grafana_dashboard" "cluster_network_flows" {
  folder      = grafana_folder.k3s_cluster.id
  config_json = file("${path.module}/dashboards/cluster-network-flows.json")
}

resource "grafana_dashboard" "network_traffic" {
  folder      = grafana_folder.k3s_cluster.id
  config_json = file("${path.module}/dashboards/network-traffic.json")
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboards - Docker / homelab-1 (Containers, Scraparr, Traefik)
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_dashboard" "docker_hosts" {
  folder      = grafana_folder.docker_homelab1.id
  config_json = file("${path.module}/dashboards/docker-hosts.json")
}

resource "grafana_dashboard" "scraparr" {
  folder      = grafana_folder.docker_homelab1.id
  config_json = file("${path.module}/dashboards/scraparr.json")
}

resource "grafana_dashboard" "traefik" {
  # Covers all 3 Traefik instances (proxy-lxc, VPS/pangolin, K3s) via the
  # dashboard's job template variable — pick an instance from the dropdown.
  folder      = grafana_folder.docker_homelab1.id
  config_json = file("${path.module}/dashboards/traefik.json")
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboards - Applications
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_dashboard" "k8s_learn" {
  folder      = grafana_folder.applications.id
  config_json = file("${path.module}/dashboards/k8s-learn.json")
}

# ─────────────────────────────────────────────────────────────────────────────
# Dashboards - VPS (Health, CrowdSec, Pangolin)
# ─────────────────────────────────────────────────────────────────────────────

resource "grafana_dashboard" "vps_health" {
  folder      = grafana_folder.vps.id
  config_json = file("${path.module}/dashboards/vps-security.json")
}

resource "grafana_dashboard" "pangolin" {
  folder      = grafana_folder.vps.id
  config_json = file("${path.module}/dashboards/pangolin.json")
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "folders" {
  description = "Created Grafana folders"
  value = {
    infrastructure  = grafana_folder.infrastructure.id
    k3s_cluster     = grafana_folder.k3s_cluster.id
    docker_homelab1 = grafana_folder.docker_homelab1.id
    applications    = grafana_folder.applications.id
    vps             = grafana_folder.vps.id
  }
}

output "datasources" {
  description = "Grafana data sources (provisioned by Helm)"
  value = {
    prometheus   = data.grafana_data_source.prometheus.id
    loki         = data.grafana_data_source.loki.id
    alertmanager = data.grafana_data_source.alertmanager.id
  }
}

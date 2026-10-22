# Grafana Terraform Configuration

This Terraform configuration manages Grafana dashboards and folders as code.

## Prerequisites

1. Grafana running in K3s cluster
2. A service account with Admin role in Grafana
3. Service account token
4. kubectl configured with `~/.kube/homelab-k3s.yaml`

## Setup

### 1. Create Grafana Service Account

1. Go to Grafana > Administration > Service Accounts
2. Click "Add service account"
3. Name: `terraform`
4. Role: `Admin`
5. Click "Add service account token"
6. Copy the token

### 2. Configure Terraform

```bash
cd infrastructure/terraform-grafana
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
grafana_url  = "http://localhost:3000"
grafana_auth = "glsa_your_token_here"
```

### 3. Port-Forward to Grafana

Since Grafana is in the K3s cluster, tunnel to it first:

```bash
KUBECONFIG=~/.kube/homelab-k3s.yaml kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
```

### 4. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply

# Kill the port-forward when done
pkill -f "kubectl port-forward.*grafana"
```

## Dashboards

| Dashboard | Folder | Description |
|-----------|--------|-------------|
| Node Exporter | Infrastructure | System metrics (CPU, memory, disk, network) |
| K8s Cluster | Kubernetes | Cluster-wide resource overview |
| K8s Pods | Kubernetes | Pod-level metrics and status |
| K8s Namespaces | Kubernetes | Namespace resource breakdown |
| Traefik | Applications | Ingress traffic and latency |
| Longhorn | Applications | Distributed storage metrics |
| Proxmox | Homelab | Virtualization host metrics |
| Docker Hosts | Homelab | Container metrics on Docker VMs |
| VPS Overview | VPS | Hostinger VPS health |
| CrowdSec | VPS | Security alerts and decisions |

## Adding New Dashboards

1. Create a JSON file in `dashboards/`
2. Add a `grafana_dashboard` resource in `main.tf`:

```hcl
resource "grafana_dashboard" "my_dashboard" {
  folder      = grafana_folder.applications.id
  config_json = file("${path.module}/dashboards/my-dashboard.json")
}
```

3. Run `terraform apply`

## Importing Existing Dashboards

Export a dashboard from Grafana UI (Share > Export > Save to file), then:

1. Save JSON to `dashboards/`
2. Add the resource to `main.tf`
3. Import: `terraform import grafana_dashboard.my_dashboard <uid>`

## Data Sources

Currently configured:

- **Prometheus** - Metrics (default)
- **Loki** - Logs
- **Alertmanager** - Alerts

To add more, create `grafana_data_source` resources in `main.tf`.

## Outputs

After applying:

```bash
terraform output folders
terraform output datasources
```

variable "grafana_url" {
  description = "URL of the Grafana instance"
  type        = string
  default     = "https://grafana.lab.bp31app.com"
}

variable "grafana_auth" {
  description = "Grafana API key or service account token"
  type        = string
  sensitive   = true
}

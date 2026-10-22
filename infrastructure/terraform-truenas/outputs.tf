output "dataset_ids" {
  description = "Created dataset full paths (pool/name)"
  value       = { for k, d in truenas_pool_dataset.datasets : k => d.id }
}

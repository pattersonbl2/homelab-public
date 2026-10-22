# GCS backend config for Terraform state.
# Copy to backend.gcs.hcl and set your bucket/prefix. backend.gcs.hcl is gitignored.
#
# One-time setup:
#   1. Create a GCS bucket (e.g. gcloud storage buckets create gs://YOUR_PROJECT-terraform-state --location=us-central1)
#   2. cp backend.gcs.example.hcl backend.gcs.hcl
#   3. Edit backend.gcs.hcl with your bucket and prefix
#   4. gcloud auth application-default login   # or set GOOGLE_APPLICATION_CREDENTIALS
#   5. terraform init -reconfigure -backend-config=backend.gcs.hcl
#
# Migrating from local state (first time):
#   terraform init -migrate-state -reconfigure -backend-config=backend.gcs.hcl

bucket = "YOUR_GCS_BUCKET"
prefix = "homelab/docker-hosts"

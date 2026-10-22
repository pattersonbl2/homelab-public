# Terraform – Docker hosts + Tailscale LXC

Provisions Proxmox VMs (Docker hosts, OpenClaw) and the Tailscale LXC subnet router.

## GCS backend (state)

State is configured to use a **GCS backend**. You must create the config file and run init before first use (or after clone).

1. **Create a GCS bucket** (one-time):
   ```bash
   gcloud storage buckets create gs://YOUR_PROJECT-terraform-state --location=us-central1
   ```
   Or use an existing bucket.

2. **Create backend config** (do not commit; it’s gitignored):
   ```bash
   cp backend.gcs.example.hcl backend.gcs.hcl
   # Edit backend.gcs.hcl: set bucket = "your-bucket", prefix = "homelab/docker-hosts"
   ```

3. **Auth** (if not already):
   ```bash
   gcloud auth application-default login
   ```

4. **Init (new clone or first time)**:
   ```bash
   terraform init -reconfigure -backend-config=backend.gcs.hcl
   ```

5. **Migrate from local state** (if you had state in this dir before):
   ```bash
   terraform init -migrate-state -reconfigure -backend-config=backend.gcs.hcl
   ```
   Confirm when prompted to copy existing state to GCS.

After that, use `terraform plan` / `terraform apply` as usual; state is read from and written to GCS.

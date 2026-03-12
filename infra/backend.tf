# Remote State Backend: DigitalOcean Spaces (S3-compatible)
#
# BOOTSTRAP REQUIREMENTS (one-time manual steps before `terraform init`):
#
# 1. Create the Spaces bucket manually via DO control panel or doctl:
#      doctl serverless functions list  # verify doctl is authenticated
#      # Create bucket at: https://cloud.digitalocean.com/spaces
#    Change the `bucket` value below to match your actual Spaces bucket name.
#
# 2. Authentication uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
#    environment variables. These are your DigitalOcean Spaces access keys,
#    NOT AWS credentials. Generate them at:
#      https://cloud.digitalocean.com/account/api/spaces
#
#    export AWS_ACCESS_KEY_ID="<your-spaces-access-key>"
#    export AWS_SECRET_ACCESS_KEY="<your-spaces-secret-key>"
#
# 3. The DigitalOcean API token (DIGITALOCEAN_TOKEN) is a SEPARATE credential
#    used by the provider -- it does NOT authenticate the backend.

terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://nyc3.digitaloceanspaces.com"
    }

    bucket = "odoo-prod-tfstate"
    key    = "terraform.tfstate"

    # Required by S3 backend but unused by DigitalOcean
    region = "us-east-1"

    # Required flags for non-AWS S3-compatible backends
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}

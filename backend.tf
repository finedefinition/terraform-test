terraform {
  backend "s3" {
    # Backend configuration cannot use variables
    # Configure these values using terraform init -backend-config=backend-config.hcl
  }
}

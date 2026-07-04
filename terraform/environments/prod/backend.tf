# Remote state backend for the prod environment.
# Same bucket and DynamoDB table as dev, isolated by state key.
# Bucket and DynamoDB table are provisioned once via scripts/bootstrap-state.sh
# (see docs/technical-spec.md#terraform-state-backend).
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-072988571347"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}

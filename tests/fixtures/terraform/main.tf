# Fixture of ci-cd.yml's ci-terraform job: a module with no provider to
# download, which terraform validate, terraform fmt, tflint and the
# configuration scan all accept.
terraform {
  required_version = ">= 1.5"
}

variable "name" {
  description = "Name recorded by the fixture resource"
  type        = string
  default     = "ci-selftest"
}

resource "terraform_data" "fixture" {
  input = var.name
}

output "name" {
  description = "The recorded name"
  value       = terraform_data.fixture.output
}

locals {
  labels = merge(var.labels, { managed-by = "opentofu", module = "demo-bucket" })
}

# Placeholder: replace with the real resources for this module.
resource "terraform_data" "this" {
  input = {
    name   = var.name
    labels = local.labels
  }
}

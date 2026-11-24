locals {
  labels = merge(var.labels, { managed-by = "opentofu", module = "__MODULE_NAME__" })
}

# Placeholder: replace with the real resources for this module.
resource "terraform_data" "this" {
  input = {
    name   = var.name
    labels = local.labels
  }
}

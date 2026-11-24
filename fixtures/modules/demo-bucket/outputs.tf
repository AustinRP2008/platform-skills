output "name" {
  description = "Name of the managed resource."
  value       = var.name
}

output "labels" {
  description = "Effective labels, including platform defaults."
  value       = local.labels
}

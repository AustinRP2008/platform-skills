variable "name" {
  description = "Name of the resource this module manages."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.name))
    error_message = "name must be 4-63 chars of lowercase letters, digits and hyphens."
  }
}

variable "labels" {
  description = "Extra labels applied to every resource."
  type        = map(string)
  default     = {}
}

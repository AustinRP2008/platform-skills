# Generic golden-image build. All inputs come from image.yaml via build.sh / validate.sh; do not edit per image.
packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "~> 1.1"
    }
  }
}

variable "name" {
  type = string
}

variable "base" {
  type = string
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.base))
    error_message = "The base image must be pinned by digest."
  }
}

variable "channel" {
  type    = string
  default = "dev"
}

variable "owner" {
  type = string
}

variable "packages" {
  type    = string
  default = "ca-certificates"
}

source "docker" "base" {
  image  = var.base
  commit = true
  changes = [
    "USER 10001",
    "WORKDIR /home/app",
    "LABEL org.opencontainers.image.title=${var.name}",
    "LABEL org.opencontainers.image.base.name=${var.base}",
    "LABEL platform.local/owner=${var.owner}",
    "LABEL platform.local/channel=${var.channel}",
  ]
}

build {
  sources = ["source.docker.base"]

  provisioner "shell" {
    environment_vars = ["PACKAGES=${var.packages}"]
    script           = "${path.root}/files/harden.sh"
  }

  post-processor "docker-tag" {
    repository = "local/golden/${var.name}"
    tags       = [var.channel]
  }
}

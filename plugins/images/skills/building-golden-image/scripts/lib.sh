# shellcheck shell=bash
# Shared helpers: read image.yaml into packer -var flags.
packer_vars() { # <image-dir> -> prints one -var=... per line
  yq -o=json '.' "$1/image.yaml" | jq -r '
    "-var=name=\(.metadata.name)", "-var=owner=\(.metadata.owner)", "-var=base=\(.spec.base)",
    "-var=channel=\(.spec.channel)", "-var=packages=\(.spec.packages | join(" "))"'
}

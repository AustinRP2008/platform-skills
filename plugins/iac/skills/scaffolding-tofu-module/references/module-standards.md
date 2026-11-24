# Module standards

- `versions.tf` pins `required_version` and every provider with `~>`.
- Every variable has `description` and `type`; enums and formats get a `validation` block.
- Every output has a `description`. Never output secrets; mark sensitive values `sensitive = true`.
- Labels/tags: accept `labels` (map(string)) and merge in `managed-by = "opentofu"`.
- No provider blocks inside modules; the caller configures providers.
- Tests: `tests/*.tftest.hcl`, `command = plan` by default, `mock_provider` for every provider.
- README inputs/outputs are generated (terraform-docs) — do not hand-edit between the markers.

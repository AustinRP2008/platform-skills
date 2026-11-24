variables {
  name = "example-thing"
}

run "applies_platform_labels" {
  command = plan

  assert {
    condition     = output.labels["managed-by"] == "opentofu"
    error_message = "managed-by label must be set"
  }
}

run "rejects_bad_names" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

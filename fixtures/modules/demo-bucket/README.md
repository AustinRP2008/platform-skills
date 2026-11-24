# demo-bucket

Fixture module for the reusable-workflow self-test.

## Usage

```hcl
module "demo_bucket" {
  source = "git::https://github.com/<owner>/<repo>.git//modules/demo-bucket?ref=<tag>"
  name   = "example"
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

# Minimal root "module" for the test suite. terraform test runs against a
# root module directory (this one) and discovers *.tftest.hcl files here.
# There is no real infrastructure defined at this level -- each test's
# `module` block points at the actual module under test (../modules/vpc,
# ../modules/eks), and mock_provider "aws" {} in each test file means
# `terraform test` never contacts AWS.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

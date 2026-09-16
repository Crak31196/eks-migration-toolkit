# Native Terraform tests for the vpc module.
#
# These run entirely offline: mock_provider "aws" {} fabricates plausible
# resource state for every aws_* resource so `terraform test` never needs
# real AWS credentials or network access. That means these tests validate
# module wiring/logic and variable validation, not real AWS API behavior.

mock_provider "aws" {}

variables {
  name                 = "test-demo"
  cluster_name         = "test-demo-eks"
  cidr_block           = "10.50.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.50.0.0/24", "10.50.1.0/24"]
  private_subnet_cidrs = ["10.50.10.0/24", "10.50.11.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
}

run "creates_expected_private_subnets" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  assert {
    condition     = length(aws_subnet.private) == length(var.azs)
    error_message = "Expected one private subnet per availability zone."
  }

  assert {
    condition     = length(aws_subnet.public) == length(var.azs)
    error_message = "Expected one public subnet per availability zone."
  }

  assert {
    # map_public_ip_on_launch is Optional (not Computed) in the AWS provider
    # schema and defaults to false in the AWS API itself; since we never set
    # it on the private subnet, the mocked plan value is null rather than a
    # concrete false, so we assert it is not explicitly true.
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch != true])
    error_message = "Private subnets must not auto-assign public IPs."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == true])
    error_message = "Public subnets should auto-assign public IPs for internet-facing load balancers."
  }
}

run "nat_gateway_created_when_enabled" {
  command = plan

  module {
    source = "../modules/vpc"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway=true should create exactly one NAT gateway."
  }
}

run "nat_gateway_skipped_when_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  module {
    source = "../modules/vpc"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "enable_nat_gateway=false should create zero NAT gateways to avoid unnecessary cost."
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "enable_nat_gateway=false should not allocate any Elastic IPs."
  }
}

run "rejects_mismatched_subnet_and_az_counts" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.50.0.0/24"] # only 1 CIDR but 2 AZs
  }

  module {
    source = "../modules/vpc"
  }

  expect_failures = [
    var.public_subnet_cidrs,
  ]
}

run "rejects_invalid_cidr_block" {
  command = plan

  variables {
    cidr_block = "not-a-cidr"
  }

  module {
    source = "../modules/vpc"
  }

  expect_failures = [
    var.cidr_block,
  ]
}

run "rejects_single_az" {
  command = plan

  variables {
    azs                  = ["us-east-1a"]
    public_subnet_cidrs  = ["10.50.0.0/24"]
    private_subnet_cidrs = ["10.50.10.0/24"]
  }

  module {
    source = "../modules/vpc"
  }

  expect_failures = [
    var.azs,
  ]
}

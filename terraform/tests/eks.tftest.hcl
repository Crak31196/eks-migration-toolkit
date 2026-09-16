# Native Terraform tests for the eks module.
#
# mock_provider "aws" {} means these tests never touch a real AWS account.
# The aws_eks_cluster resource's computed `identity`/`oidc` attributes are
# consumed by the OIDC provider and IRSA role resources further down the
# module, so we give the mock a plausible shape via override_resource --
# otherwise the mocked value defaults to an empty list and indexing into it
# would fail the plan.

mock_provider "aws" {
  override_resource {
    target = aws_eks_cluster.this
    values = {
      arn      = "arn:aws:eks:us-east-1:123456789012:cluster/test-demo-eks"
      endpoint = "https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
      identity = [
        {
          oidc = [
            {
              issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
            }
          ]
        }
      ]
      certificate_authority = [
        {
          data = "ZmFrZS1jYS1kYXRhLWZvci10ZXN0aW5n"
        }
      ]
    }
  }

  # aws_iam_policy_document is a data source, so its `json` attribute is
  # normally computed by the (real) provider's own rendering logic. Under
  # mock_provider that logic never runs, so without an override the mocked
  # `json` value is a placeholder string that is not valid JSON -- which the
  # aws_iam_role/aws_iam_policy resources reject at plan time. We override it
  # with a minimal-but-valid IAM policy document for every policy document
  # data source in this module.
  override_data {
    target = data.aws_iam_policy_document.cluster_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"eks.amazonaws.com\"}}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.node_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.cluster_autoscaler_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.cluster_autoscaler_policy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  cluster_name        = "test-demo-eks"
  cluster_version     = "1.30"
  vpc_id              = "vpc-0123456789abcdef0"
  private_subnet_ids  = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  public_subnet_ids   = ["subnet-0ccccccccccccccc", "subnet-0ddddddddddddddd"]
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 4
  node_capacity_type  = "ON_DEMAND"
}

run "plan_produces_expected_resources" {
  command = plan

  module {
    source = "../modules/eks"
  }

  assert {
    condition     = aws_eks_cluster.this.name == var.cluster_name
    error_message = "Cluster name should match the cluster_name variable."
  }

  assert {
    condition     = length(aws_eks_node_group.this.subnet_ids) == 2
    error_message = "Node group should be placed in the private subnets."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == var.node_desired_size
    error_message = "Node group desired size should match node_desired_size."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true
    error_message = "Default endpoint_public_access should be true."
  }
}

run "creates_oidc_provider_and_autoscaler_role_by_default" {
  command = plan

  module {
    source = "../modules/eks"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.this.client_id_list) == 1
    error_message = "OIDC provider should register exactly one audience (sts.amazonaws.com)."
  }

  assert {
    condition     = length(aws_iam_role.cluster_autoscaler) == 1
    error_message = "Cluster autoscaler IRSA role should be created when enable_cluster_autoscaler_irsa is true (default)."
  }
}

run "skips_autoscaler_role_when_disabled" {
  command = plan

  variables {
    enable_cluster_autoscaler_irsa = false
  }

  module {
    source = "../modules/eks"
  }

  assert {
    condition     = length(aws_iam_role.cluster_autoscaler) == 0
    error_message = "Cluster autoscaler IRSA role should not be created when enable_cluster_autoscaler_irsa is false."
  }

  assert {
    condition     = length(aws_iam_policy.cluster_autoscaler) == 0
    error_message = "Cluster autoscaler IAM policy should not be created when enable_cluster_autoscaler_irsa is false."
  }
}

run "rejects_max_size_below_min_size" {
  command = plan

  variables {
    node_min_size = 5
    node_max_size = 2
  }

  module {
    source = "../modules/eks"
  }

  expect_failures = [
    var.node_max_size,
  ]
}

run "rejects_invalid_capacity_type" {
  command = plan

  variables {
    node_capacity_type = "RESERVED"
  }

  module {
    source = "../modules/eks"
  }

  expect_failures = [
    var.node_capacity_type,
  ]
}

run "rejects_single_private_subnet" {
  command = plan

  variables {
    private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
  }

  module {
    source = "../modules/eks"
  }

  expect_failures = [
    var.private_subnet_ids,
  ]
}

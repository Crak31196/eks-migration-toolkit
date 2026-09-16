# EKS module
#
# Provisions a managed EKS cluster, a managed node group, the IAM
# OIDC provider needed for IRSA (IAM Roles for Service Accounts), an
# example IRSA role for the Kubernetes Cluster Autoscaler, and the
# security groups controlling traffic between the control plane and the
# worker nodes.
#
# Note on the OIDC thumbprint: AWS has not validated the thumbprint_list
# value for EKS-issued OIDC providers since mid-2022, but the IAM API still
# requires the argument to be present. We default to the well-known root CA
# thumbprint used across the Terraform AWS community rather than fetching it
# live via the `tls` provider, so this module can be planned/tested (and
# imported) with zero external network calls.

locals {
  merged_tags = merge(
    var.tags,
    {
      "Project"   = var.cluster_name
      "ManagedBy" = "terraform"
    }
  )

  oidc_issuer_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# ---------------------------------------------------------------------------
# IAM: cluster role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.merged_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Additional security group for the EKS control plane ENIs"
  vpc_id      = var.vpc_id

  tags = merge(local.merged_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "Security group for EKS managed node group worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.merged_tags, {
    Name                                        = "${var.cluster_name}-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}

# Control plane -> nodes: kubelet and extension API servers.
resource "aws_security_group_rule" "cluster_to_nodes" {
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Control plane to worker node kubelet/extension API"
}

# Nodes -> control plane: HTTPS API.
resource "aws_security_group_rule" "nodes_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Worker nodes to control plane HTTPS API"
}

# Control plane -> nodes on HTTPS (webhooks, metrics-server, etc.).
resource "aws_security_group_rule" "cluster_to_nodes_https" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Control plane to worker node HTTPS (webhooks/metrics-server)"
}

# Node <-> node: required for CNI, DNS, and inter-pod traffic.
resource "aws_security_group_rule" "nodes_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.nodes.id
  self              = true
  description       = "Node to node traffic (CNI, CoreDNS, pod-to-pod)"
}

# Control plane -> nodes: kubelet/extension API ingress on the node side.
resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Control plane to worker node kubelet/extension API"
}

resource "aws_security_group_rule" "nodes_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Nodes need outbound access (ECR, pulling images, AWS APIs via NAT)"
}

# ---------------------------------------------------------------------------
# EKS cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # CKS-aligned baseline: turn on control plane audit/authenticator logging
  # so cluster access and API activity are captured from day one.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = local.merged_tags

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ---------------------------------------------------------------------------
# IAM: node role + managed node group
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = local.merged_tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "workload" = "general"
  }

  tags = local.merged_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------------
# IRSA: OIDC provider + Cluster Autoscaler role
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.oidc_thumbprint]

  tags = local.merged_tags
}

data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  count = var.enable_cluster_autoscaler_irsa ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  count              = var.enable_cluster_autoscaler_irsa ? 1 : 0
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role[0].json
  tags               = local.merged_tags
}

data "aws_iam_policy_document" "cluster_autoscaler_policy" {
  count = var.enable_cluster_autoscaler_irsa ? 1 : 0

  statement {
    sid    = "ClusterAutoscalerDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ClusterAutoscalerMutate"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler_irsa ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler"
  description = "Least-privilege policy allowing the Kubernetes Cluster Autoscaler to scale this cluster's node group"
  policy      = data.aws_iam_policy_document.cluster_autoscaler_policy[0].json
  tags        = local.merged_tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enable_cluster_autoscaler_irsa ? 1 : 0
  role       = aws_iam_role.cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
}

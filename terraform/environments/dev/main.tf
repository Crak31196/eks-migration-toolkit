# dev environment root module
#
# Wires the vpc and eks modules together into a single deployable EKS
# cluster. This is the module a client would point `terraform apply` at
# after copying terraform.tfvars.example to terraform.tfvars and filling in
# real values.

module "vpc" {
  source = "../../modules/vpc"

  name                 = var.name_prefix
  cluster_name         = "${var.name_prefix}-eks"
  cidr_block           = var.vpc_cidr_block
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway

  tags = {
    Environment = var.environment
  }
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = "${var.name_prefix}-eks"
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_capacity_type  = var.node_capacity_type

  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  tags = {
    Environment = var.environment
  }
}

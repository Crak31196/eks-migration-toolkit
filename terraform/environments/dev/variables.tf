variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used for tagging and naming."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Prefix applied to all resource names (VPC, cluster, IAM roles)."
  type        = string
  default     = "eks-migration-demo"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must start with a letter, be 2-31 characters, and contain only letters, numbers, and hyphens."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, index-aligned with var.azs."
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, index-aligned with var.azs."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to provision NAT gateway(s) for private subnet egress. Set to false to save cost when only exercising the Terraform plan/test workflow."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ, to reduce cost in dev."
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "endpoint_public_access" {
  description = "Whether the EKS API endpoint is reachable from the public internet."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Restrict this to your office/VPN CIDR for anything beyond a demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

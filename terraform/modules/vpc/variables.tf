variable "name" {
  description = "Name prefix applied to all VPC resources and used in the required EKS subnet tags."
  type        = string

  validation {
    condition     = length(var.name) > 0 && can(regex("^[a-zA-Z0-9-]+$", var.name))
    error_message = "name must be a non-empty string containing only letters, numbers, and hyphens."
  }
}

variable "cidr_block" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "List of availability zones to spread subnets across. At least 2 are required for EKS control plane HA."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least 2 availability zones are required for an EKS-ready VPC."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ (index-aligned with var.azs)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have exactly one CIDR per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ (index-aligned with var.azs). Worker nodes and pods live here."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have exactly one CIDR per availability zone."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT gateway for private subnet egress. Disable in dev/demo to avoid NAT Gateway hourly + data processing charges; private nodes will have no outbound internet access without it."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "When enable_nat_gateway is true, use a single shared NAT gateway (cheaper, less resilient) instead of one per AZ (recommended for production)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster that will use this VPC, used for the kubernetes.io/cluster/<name> subnet tags required by the AWS VPC CNI and the AWS Load Balancer Controller."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

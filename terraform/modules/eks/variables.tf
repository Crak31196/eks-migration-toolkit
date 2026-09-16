variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_name))
    error_message = "cluster_name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.cluster_version))
    error_message = "cluster_version must look like a Kubernetes minor version, e.g. \"1.30\"."
  }
}

variable "vpc_id" {
  description = "VPC ID the cluster and node group will be deployed into."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the managed node group (and the control plane ENIs)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for EKS control plane and node group HA."
  }
}

variable "public_subnet_ids" {
  description = "Public subnet IDs, only used if endpoint_public_access requires an internet-facing path (kept for future ALB/ingress use)."
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Whether the EKS cluster API endpoint is reachable from inside the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS cluster API endpoint is reachable from the public internet. Recommended to restrict via public_access_cidrs in production, aligned with the CKS-style least-privilege posture this toolkit follows."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint when endpoint_public_access is true. Defaults to open; restrict this for any real deployment."
  type        = list(string)
  default     = ["0.0.0.0/0"]
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

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes (used by the cluster autoscaler)."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (used by the cluster autoscaler)."
  type        = number
  default     = 4

  validation {
    condition     = var.node_max_size >= var.node_min_size
    error_message = "node_max_size must be greater than or equal to node_min_size."
  }
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 50
}

variable "oidc_thumbprint" {
  description = "SHA1 thumbprint of the OIDC issuer's root CA, required by aws_iam_openid_connect_provider. AWS has not validated this value for EKS since 2022, so the well-known community default is safe to keep; override only if your organization requires a specific value."
  type        = string
  default     = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
}

variable "enable_cluster_autoscaler_irsa" {
  description = "Whether to create the IRSA role/policy that the Kubernetes Cluster Autoscaler add-on assumes to scale the managed node group."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

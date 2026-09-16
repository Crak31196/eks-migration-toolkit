output "vpc_id" {
  description = "ID of the VPC created for this environment."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the EKS node group."
  value       = module.vpc.private_subnet_ids
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider, for wiring additional IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN to annotate the cluster-autoscaler service account with."
  value       = module.eks.cluster_autoscaler_role_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl against this cluster once applied for real."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_id}"
}

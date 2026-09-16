output "cluster_id" {
  description = "Name/ID of the EKS cluster."
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster, used to configure kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the additional control-plane security group."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "ID of the worker node security group."
  value       = aws_security_group.nodes.id
}

output "node_group_id" {
  description = "ID of the managed node group."
  value       = aws_eks_node_group.this.id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider created for IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "URL of the cluster's OIDC issuer (without the https:// prefix)."
  value       = local.oidc_issuer_host
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the IRSA role for the Cluster Autoscaler, if created."
  value       = var.enable_cluster_autoscaler_irsa ? aws_iam_role.cluster_autoscaler[0].arn : null
}

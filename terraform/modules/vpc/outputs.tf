output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the created VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (for internet-facing load balancers)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (for EKS worker nodes and pods)."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateway(s), if enabled. Empty list when enable_nat_gateway is false."
  value       = aws_nat_gateway.this[*].id
}

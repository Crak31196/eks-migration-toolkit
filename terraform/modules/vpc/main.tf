# VPC module
#
# Builds a VPC with public and private subnets spread across the given
# availability zones, tagged so the EKS control plane, the AWS VPC CNI, and
# the AWS Load Balancer Controller can auto-discover them. NAT gateway
# creation is a toggle so this can be run cheaply for demos/dev (no NAT =
# private subnets have no outbound internet, which is fine for testing the
# module plan but not for a real workload).

locals {
  merged_tags = merge(
    var.tags,
    {
      "Project"   = var.name
      "ManagedBy" = "terraform"
    }
  )

  # Only build NAT gateways/EIPs when enabled. When single_nat_gateway is
  # true we create exactly one, otherwise one per AZ for HA egress.
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.merged_tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.merged_tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.merged_tags, {
    Name                                        = "${var.name}-public-${var.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.merged_tags, {
    Name                                        = "${var.name}-private-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.merged_tags, {
    Name = "${var.name}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  # Single NAT gateway lives in the first public subnet; one-per-AZ aligns
  # index-to-index with the public subnets.
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(local.merged_tags, {
    Name = "${var.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.merged_tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  # One route table per private subnet when using per-AZ NAT gateways, or a
  # single shared one when there's only one NAT gateway (or none at all).
  count  = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : 1
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[route.key].id
    }
  }

  tags = merge(local.merged_tags, {
    Name = "${var.name}-private-rt-${count.index}"
  })
}

resource "aws_route_table_association" "private" {
  count     = length(aws_subnet.private)
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = (
    var.enable_nat_gateway && !var.single_nat_gateway
    ? aws_route_table.private[count.index].id
    : aws_route_table.private[0].id
  )
}

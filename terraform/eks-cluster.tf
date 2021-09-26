terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"
}

# Create a VPC
resource "aws_vpc" "eks-vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC for EKS cluster"
  }
}

# Create the subnets
resource "aws_subnet" "eks-public-subnet-01" {
  vpc_id            = aws_vpc.eks-vpc.id
  cidr_block        = "192.168.0.0/18"
  availability_zone = "us-east-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet 01 for EKS Cluster",
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "eks-public-subnet-02" {
  vpc_id            = aws_vpc.eks-vpc.id
  cidr_block        = "192.168.64.0/18"
  availability_zone = "us-east-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public Subnet 02 for EKS Cluster",
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "eks-private-subnet-01" {
  vpc_id            = aws_vpc.eks-vpc.id
  cidr_block        = "192.168.128.0/18"
  availability_zone = "us-east-2a"

  tags = {
    Name = "Private Subnet 01 for EKS Cluster",
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "eks-private-subnet-02" {
  vpc_id            = aws_vpc.eks-vpc.id
  cidr_block        = "192.168.192.0/18"
  availability_zone = "us-east-2b"

  tags = {
    Name = "Private Subnet 02 for EKS Cluster",
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "eks-internet-gateway" {
  vpc_id = aws_vpc.eks-vpc.id

  tags = {
    Name = "EKS Cluster Internet Gateway"
  }
}

# EIP
resource "aws_eip" "eks-public-eip-01" {
  vpc         = true
  depends_on  = [aws_internet_gateway.eks-internet-gateway]
}

resource "aws_eip" "eks-public-eip-02" {
  vpc         = true
  depends_on  = [aws_internet_gateway.eks-internet-gateway]
}

# Create NAT Gateways
resource "aws_nat_gateway" "eks-public-nat-gateway-01" {
  allocation_id = aws_eip.eks-public-eip-01.id
  subnet_id     = aws_subnet.eks-public-subnet-01.id
  depends_on    = [aws_internet_gateway.eks-internet-gateway, aws_subnet.eks-public-subnet-01]
}

resource "aws_nat_gateway" "eks-public-nat-gateway-02" {
  allocation_id = aws_eip.eks-public-eip-02.id
  subnet_id     = aws_subnet.eks-public-subnet-02.id
  depends_on    = [aws_internet_gateway.eks-internet-gateway, aws_subnet.eks-public-subnet-02]
}

# Create Route Tables
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.eks-vpc.id
  depends_on  = [aws_internet_gateway.eks-internet-gateway]
  route = [
    {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.eks-internet-gateway.id
      egress_only_gateway_id     = ""
      instance_id                = ""
      nat_gateway_id             = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_peering_connection_id  = ""
      carrier_gateway_id         = ""
      destination_prefix_list_id = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      vpc_endpoint_id            = ""
    }
  ] 
}

resource "aws_route_table" "private-route-table-01" {
  vpc_id = aws_vpc.eks-vpc.id

  route = [
    {
      cidr_block = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.eks-public-nat-gateway-01.id
      gateway_id                 = ""
      egress_only_gateway_id     = ""
      instance_id                = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_peering_connection_id  = ""
      carrier_gateway_id         = ""
      destination_prefix_list_id = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      vpc_endpoint_id            = ""
    }
  ]

  depends_on  = [aws_nat_gateway.eks-public-nat-gateway-01]
}

resource "aws_route_table" "private-route-table-02" {
  vpc_id = aws_vpc.eks-vpc.id

  route = [
    {
      cidr_block = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.eks-public-nat-gateway-02.id
      gateway_id                 = ""
      egress_only_gateway_id     = ""
      instance_id                = ""
      network_interface_id       = ""
      transit_gateway_id         = ""
      vpc_peering_connection_id  = ""
      carrier_gateway_id         = ""
      destination_prefix_list_id = ""
      ipv6_cidr_block            = ""
      local_gateway_id           = ""
      vpc_endpoint_id            = ""
    }
  ]

  depends_on  = [aws_nat_gateway.eks-public-nat-gateway-02]
}

# Assign Route Tables
resource "aws_route_table_association" "eks-public-01" {
  subnet_id      = aws_subnet.eks-public-subnet-01.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "eks-public-02" {
  subnet_id      = aws_subnet.eks-public-subnet-02.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "eks-private-01" {
  subnet_id      = aws_subnet.eks-private-subnet-01.id
  route_table_id = aws_route_table.private-route-table-01.id
}

resource "aws_route_table_association" "eks-private-02" {
  subnet_id      = aws_subnet.eks-private-subnet-02.id
  route_table_id = aws_route_table.private-route-table-02.id
}

# Create Security Group
resource "aws_security_group" "eks-control-plane-securitygroup" {
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.eks-vpc.id
}

# Create EKS IAM roles
resource "aws_iam_role" "eks-cluster-role" {
  name = "Terraform-EKSClusterRole"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster-role.name
}

# Optionally, enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks-cluster-role.name
}

# Create Worker Nodes IAM Roles
resource "aws_iam_role" "eks-worker-role" {
  name = "Terraform-EKSNodeGroupRole"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-worker-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-worker-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-worker-role.name
}

# Create EKS Cluster
resource "aws_eks_cluster" "eks-cluster" {
  name     = "terraform-eks-cluster"
  role_arn = aws_iam_role.eks-cluster-role.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks-public-subnet-01.id, aws_subnet.eks-public-subnet-02.id, aws_subnet.eks-private-subnet-01.id, aws_subnet.eks-private-subnet-02.id]
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSVPCResourceController,
  ]
}

# Create Node Group
resource "aws_eks_node_group" "eks-node-group" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "terraform-eks-node-group"
  node_role_arn   = aws_iam_role.eks-worker-role.arn
  subnet_ids      = [aws_subnet.eks-public-subnet-01.id, aws_subnet.eks-public-subnet-02.id, aws_subnet.eks-private-subnet-01.id, aws_subnet.eks-private-subnet-02.id]

  instance_types = ["t2.small"]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  update_config {
    max_unavailable = 2
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}
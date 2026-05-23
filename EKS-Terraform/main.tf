terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################
# VARIABLES
############################

variable "cluster_version" {
  description = "Amazon EKS Kubernetes version."
  default     = "1.35"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access to the helper instance."
  type        = string
  default     = "threetier"
}

############################
# VPC
############################

resource "aws_vpc" "eks_vpc" {

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.eks_vpc.id
}

############################
# SUBNETS
############################

resource "aws_subnet" "public1" {

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "eks-public-1"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public2" {

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "eks-public-2"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private1" {

  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name                              = "eks-private-1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private2" {

  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name                              = "eks-private-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

############################
# NAT GATEWAY
############################

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {

  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1.id
}

############################
# ROUTE TABLES
############################

resource "aws_route_table" "public" {

  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub1" {

  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub2" {

  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {

  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "priv1" {

  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "priv2" {

  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "allow_all" {

  name        = "allow-all-sg"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {

    description = "Allow all inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {

    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-all-sg"
  }
}
############################
# IAM ROLE - CLUSTER
############################

resource "aws_iam_role" "cluster_role" {

  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {

  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

############################
# IAM ROLE - NODE GROUP
############################

resource "aws_iam_role" "worker_role" {

  name = "eks-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node" {

  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {

  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr" {

  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################
# IAM ROLE - HELPER EC2
############################

resource "aws_iam_role" "helper_instance_role" {

  name = "eks-helper-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "helper_ssm" {

  role       = aws_iam_role.helper_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "helper_eks_access" {

  name        = "eks-helper-access-policy"
  description = "Allow the helper EC2 instance to discover and describe EKS clusters."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "helper_eks_access" {

  role       = aws_iam_role.helper_instance_role.name
  policy_arn = aws_iam_policy.helper_eks_access.arn
}

resource "aws_iam_instance_profile" "helper_instance_profile" {
  name = "eks-helper-instance-profile"
  role = aws_iam_role.helper_instance_role.name
}

############################
# EKS CLUSTER
############################

resource "aws_eks_cluster" "eks" {

  name     = "naresh"
  role_arn = aws_iam_role.cluster_role.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {

    subnet_ids = [
      aws_subnet.private1.id,
      aws_subnet.private2.id
    ]

    endpoint_public_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

############################
# NODE GROUP
############################

resource "aws_eks_node_group" "node_group" {

  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "eks-node-group"

  node_role_arn = aws_iam_role.worker_role.arn
  version       = var.cluster_version

  subnet_ids = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]


  instance_types = ["c7i-flex.large"]

  scaling_config {

    desired_size = 6
    max_size     = 8
    min_size     = 4
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_node,
    aws_iam_role_policy_attachment.cni,
    aws_iam_role_policy_attachment.ecr
  ]
  tags = {
    Name        = "eks-node"
    Environment = "dev"
    Project     = "eks-project"
    Owner       = "veeraops"
  }
}

resource "aws_eks_access_entry" "helper_admin" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = aws_iam_role.helper_instance_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "helper_cluster_admin" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = aws_iam_role.helper_instance_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.helper_admin]
}


resource "aws_instance" "eks" {
  ami                         = "ami-0236922087fa98b6e"
  instance_type               = "c7i-flex.large"
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public1.id
  vpc_security_group_ids      = [aws_security_group.allow_all.id]
  iam_instance_profile        = aws_iam_instance_profile.helper_instance_profile.name
  user_data_replace_on_change = true
  root_block_device {
    volume_size = "30"
  }


  tags = {
    Name = "eks"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system
              yum update -y
              yum install -y curl unzip tar

              # ----------------------------- Install kubectl -----------------------------
              curl -o /tmp/kubectl https://dl.k8s.io/release/v1.35.3/bin/linux/amd64/kubectl
              chmod +x /tmp/kubectl
              mv /tmp/kubectl /usr/local/bin/kubectl

              # Verify kubectl
              kubectl version --client || true

              # ----------------------------- Install AWS CLI -----------------------------
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
              unzip -o /tmp/awscliv2.zip -d /tmp
              /tmp/aws/install --update

              # Verify AWS CLI
              aws --version || true

              # ----------------------------- Install eksctl -------------------------------
              curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
              | tar xz -C /tmp

              mv /tmp/eksctl /usr/local/bin/eksctl

              # Verify eksctl
              eksctl version || true

              EOF

}
############################
# EKS ADDONS
############################

resource "aws_eks_addon" "vpc_cni" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.node_group]
}

resource "aws_eks_addon" "coredns" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.node_group]
}

resource "aws_eks_addon" "kube_proxy" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.node_group]
}

resource "aws_eks_addon" "pod_identity" {

  cluster_name = aws_eks_cluster.eks.name
  addon_name   = "eks-pod-identity-agent"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.node_group]
}


resource "aws_iam_role" "ebs_csi_role" {

  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {

  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"

  role_arn = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}

resource "aws_eks_addon" "ebs_csi" {

  cluster_name                = aws_eks_cluster.eks.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.node_group,
    aws_eks_pod_identity_association.ebs_csi
  ]
}

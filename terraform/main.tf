# First applies use local state (./terraform.tfstate). After a successful apply:
#   1) Change the backend block below from backend "local" {} to backend "s3" {}
#   2) Run:  ./migrate-state-to-s3.sh  (use terraform output state_bucket_name for the bucket name)
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.32.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "state"
  region = var.s3_state_region
}

resource "random_id" "state_bucket_suffix" {
  byte_length = 4
}

locals {
  # S3 bucket names must be globally unique; suffix avoids BucketAlreadyExists (409) when a plain name is taken.
  state_bucket_name = "${var.tf_state_bucket_name}-${random_id.state_bucket_suffix.hex}"
}

resource "aws_s3_bucket" "terraform_state" {
  provider = aws.state
  bucket   = local.state_bucket_name
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  provider = aws.state
  bucket   = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  provider = aws.state
  bucket   = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Small VPC so the demo works in accounts with no default VPC (no manual subnet/SG in deploy_vars).
resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "tf-demo-vpc"
  }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
  tags = {
    Name = "tf-demo-igw"
  }
}

resource "aws_subnet" "demo_public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "tf-demo-public"
  }
}

resource "aws_route_table" "demo_public" {
  vpc_id = aws_vpc.demo.id
  tags = {
    Name = "tf-demo-public-rt"
  }
}

resource "aws_route" "demo_internet" {
  route_table_id         = aws_route_table.demo_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.demo.id
}

resource "aws_route_table_association" "demo_public" {
  subnet_id      = aws_subnet.demo_public.id
  route_table_id = aws_route_table.demo_public.id
}

resource "aws_security_group" "demo_instance" {
  name        = "tf-demo-instance-sg"
  description = "Demo instance: egress only; add SSH ingress if needed."
  vpc_id      = aws_vpc.demo.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-demo-instance-sg"
  }
}

resource "aws_instance" "tf-demo-aws-ec2-instance-1" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.demo_public.id
  vpc_security_group_ids      = [aws_security_group.demo_instance.id]
  associate_public_ip_address = true

  depends_on = [aws_route_table_association.demo_public]

  tags = {
    Name = "tf-demo-aws-ec2-instance-1"
  }
}

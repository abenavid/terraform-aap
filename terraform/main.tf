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

# --- Optional: create a VPC only when create_vpc is true
resource "aws_vpc" "main" {
  count                = var.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = var.create_vpc ? 1 : 0
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "random_id" "key_suffix" {
  byte_length = 4

  lifecycle {
    precondition {
      condition = (
        var.create_vpc && var.existing_vpc_id == "" && var.existing_subnet_id == ""
        ) || (
        !var.create_vpc && var.existing_vpc_id != "" && var.existing_subnet_id != ""
      )
      error_message = "Either set create_vpc = true and leave existing_vpc_id and existing_subnet_id empty, or set create_vpc = false and provide both existing_vpc_id and existing_subnet_id."
    }
  }
}

locals {
  vpc_id           = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  public_subnet_id = var.create_vpc ? aws_subnet.public[0].id : var.existing_subnet_id
  # Unique key name avoids InvalidKeyPair.Duplicate when state was lost but the old key still exists in AWS.
  web_key_name = var.web_demo_key_name != "" ? var.web_demo_key_name : "${var.name_prefix}-key-${random_id.key_suffix.hex}"
}

resource "aws_security_group" "instance" {
  name        = "${var.name_prefix}-instance-sg"
  description = "SSH and HTTP for demo web host"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-instance-sg"
  }
}

resource "aws_key_pair" "web_key" {
  key_name   = local.web_key_name
  public_key = var.web_demo_ssh_pubkey
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = local.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  key_name                    = aws_key_pair.web_key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name_prefix}-app"
  }
}

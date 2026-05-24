terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Default VPC + its subnets. A single seed node doesn't need bespoke
# networking, so we land it in the account's default VPC.
data "aws_vpc" "default" {
  default = true
}

# Latest Ubuntu 22.04 LTS (Jammy) amd64 server image from Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "tribe" {
  name_prefix = "tribe-prod-"
  description = "TribeEco production node: ssh, hub (443), ER (3003), ACME (80)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    description = "ACME HTTP-01 challenge (Let's Encrypt)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Hub API + wss gossip"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ER server (clients derive it as <hub-host>:3003)"
    from_port   = 3003
    to_port     = 3003
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound (Solana RPC, Let's Encrypt, Docker pulls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "tribe-prod"
    Project = "TribeEco"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "tribe" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.tribe.id]

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # cloud-init runs setup-aws.sh on first boot. Caddy retries cert
  # issuance until DNS resolves, so the box self-heals even if the A
  # record propagates after boot.
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    domain           = var.domain
    setup_url        = var.setup_url
    postgres_password = var.postgres_password
    hub_id           = var.hub_id
    solana_rpc_url   = var.solana_rpc_url
    solana_ws_url    = var.solana_ws_url
    peers            = var.peers
  })

  # Re-run user_data if the bootstrap inputs change.
  user_data_replace_on_change = true

  tags = {
    Name    = "tribe-prod"
    Project = "TribeEco"
  }
}

# Stable public IP that survives stop/start, so the DNS record never
# needs updating.
resource "aws_eip" "tribe" {
  domain = "vpc"
  tags = {
    Name    = "tribe-prod"
    Project = "TribeEco"
  }
}

resource "aws_eip_association" "tribe" {
  instance_id   = aws_instance.tribe.id
  allocation_id = aws_eip.tribe.id
}

# Optional: manage the DNS A record here too. Set route53_zone_id to let
# Terraform create seed.example.com -> Elastic IP. Leave it empty to add
# the record manually at whatever DNS provider you use.
resource "aws_route53_record" "tribe" {
  count   = var.route53_zone_id == "" ? 0 : 1
  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.tribe.public_ip]
}

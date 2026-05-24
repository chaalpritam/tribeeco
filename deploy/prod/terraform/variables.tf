variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "domain" {
  description = "Hostname for the seed node, e.g. seed.example.com. An A record (managed here or elsewhere) must point it at the Elastic IP before Caddy can issue a cert."
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH (port 22). Strongly recommend your own IP, e.g. [\"203.0.113.4/32\"], not the default."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium (4 GB) comfortably runs hub + ER + 2 Postgres; t3.small works but is tight."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_gb" {
  description = "Root EBS volume size in GB (holds Postgres data + media)."
  type        = number
  default     = 30
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID. If set, Terraform creates the A record for `domain`. Leave empty to manage DNS elsewhere."
  type        = string
  default     = ""
}

variable "setup_url" {
  description = "URL of setup-aws.sh that cloud-init fetches and runs. Override for a fork/branch."
  type        = string
  default     = "https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/prod/setup-aws.sh"
}

variable "postgres_password" {
  description = "Postgres password for both databases. Exported into the compose env on boot. Mark sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "hub_id" {
  description = "Gossip mesh id. Must be unique across all peers. Empty uses the compose default (seed-aws-1)."
  type        = string
  default     = ""
}

variable "solana_rpc_url" {
  description = "Solana RPC endpoint. Empty uses public devnet (rate-limited). Set a dedicated devnet RPC for real traffic."
  type        = string
  default     = ""
}

variable "solana_ws_url" {
  description = "Solana WS endpoint. Set alongside solana_rpc_url."
  type        = string
  default     = ""
}

variable "peers" {
  description = "Comma-separated wss gossip URLs to peer with (e.g. wss://seed.tribeapp.wtf/gossip). Empty = standalone."
  type        = string
  default     = ""
}

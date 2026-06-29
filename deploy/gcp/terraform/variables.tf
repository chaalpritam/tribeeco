variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "Google Cloud region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone."
  type        = string
  default     = "us-central1-a"
}

variable "name" {
  description = "GCE instance and resource name prefix."
  type        = string
  default     = "tribe-gcp"
}

variable "domain" {
  description = "Hostname for the node, e.g. seed.example.com."
  type        = string
}

variable "network" {
  description = "VPC network name or self link."
  type        = string
  default     = "default"
}

variable "network_tag" {
  description = "Network tag used by firewall rules."
  type        = string
  default     = "tribe-node"
}

variable "ssh_allowed_ranges" {
  description = "CIDR ranges allowed to SSH."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "machine_type" {
  description = "GCE machine type. e2-medium gives 2 vCPU / 4 GB RAM."
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_gb" {
  description = "Boot disk size in GB. Holds Docker volumes and media."
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "enable_oslogin" {
  description = "Enable Google OS Login for SSH."
  type        = bool
  default     = true
}

variable "dns_managed_zone" {
  description = "Optional Cloud DNS managed zone name. Empty means manage DNS elsewhere."
  type        = string
  default     = ""
}

variable "setup_url" {
  description = "URL of setup-gcp.sh that startup-script fetches and runs."
  type        = string
  default     = "https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/gcp/setup-gcp.sh"
}

variable "install_dir" {
  description = "Path where the repo is cloned on the VM."
  type        = string
  default     = "/opt/tribe-gcp"
}

variable "postgres_password" {
  description = "Postgres password for both databases."
  type        = string
  default     = ""
  sensitive   = true
}

variable "hub_id" {
  description = "Unique gossip mesh id. Empty uses compose default seed-gcp-1."
  type        = string
  default     = ""
}

variable "solana_rpc_url" {
  description = "Solana RPC endpoint. Empty uses public devnet."
  type        = string
  default     = ""
}

variable "solana_ws_url" {
  description = "Solana WebSocket endpoint. Set alongside solana_rpc_url."
  type        = string
  default     = ""
}

variable "peers" {
  description = "Comma-separated wss gossip URLs to peer with."
  type        = string
  default     = ""
}


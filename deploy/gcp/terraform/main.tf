terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_address" "tribe" {
  name   = "${var.name}-ip"
  region = var.region
}

resource "google_compute_firewall" "tribe_ssh" {
  name    = "${var.name}-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_allowed_ranges
  target_tags   = [var.network_tag]
}

resource "google_compute_firewall" "tribe_public" {
  name    = "${var.name}-public"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "3003"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.network_tag]
}

resource "google_compute_instance" "tribe" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.network_tag]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network = var.network

    access_config {
      nat_ip = google_compute_address.tribe.address
    }
  }

  metadata = {
    enable-oslogin = var.enable_oslogin ? "TRUE" : "FALSE"
  }

  metadata_startup_script = templatefile("${path.module}/user_data.sh.tftpl", {
    domain            = var.domain
    setup_url         = var.setup_url
    install_dir       = var.install_dir
    postgres_password = var.postgres_password
    hub_id            = var.hub_id
    solana_rpc_url    = var.solana_rpc_url
    solana_ws_url     = var.solana_ws_url
    peers             = var.peers
  })

  service_account {
    scopes = ["cloud-platform"]
  }

  labels = {
    project = "tribeeco"
  }
}

resource "google_dns_record_set" "tribe" {
  count        = var.dns_managed_zone == "" ? 0 : 1
  managed_zone = var.dns_managed_zone
  name         = "${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.tribe.address]
}


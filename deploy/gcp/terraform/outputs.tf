output "static_ip" {
  description = "Static external IP for the DNS A record."
  value       = google_compute_address.tribe.address
}

output "domain" {
  value = var.domain
}

output "zone" {
  value = var.zone
}

output "gossip_url" {
  value = "wss://${var.domain}/gossip"
}

output "hub_url" {
  value = "https://${var.domain}"
}

output "er_url" {
  value = "https://${var.domain}:3003"
}

output "next_steps" {
  value = <<EOT
1. Point ${var.domain} A record at ${google_compute_address.tribe.address} unless dns_managed_zone created it.
2. Wait for DNS: dig +short ${var.domain}
3. Watch setup: gcloud compute ssh ${google_compute_instance.tribe.name} --zone ${var.zone} --command "sudo tail -f /var/log/tribe-gcp-setup.log"
4. Verify: curl https://${var.domain}/health && curl https://${var.domain}:3003/health
5. On each Mac mini: tribe seed set wss://${var.domain}/gossip && tribe stop && tribe start
EOT
}


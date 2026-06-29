output "elastic_ip" {
  description = "Public IP. Point your DNS A record here (if not managed via route53_zone_id)."
  value       = aws_eip.tribe.public_ip
}

output "instance_id" {
  description = "EC2 instance id."
  value       = aws_instance.tribe.id
}

output "dns_managed_here" {
  description = "Whether Terraform created the A record."
  value       = var.route53_zone_id != ""
}

output "ssh" {
  description = "SSH command (uses your key pair)."
  value       = "ssh ubuntu@${aws_eip.tribe.public_ip}"
}

output "next_steps" {
  description = "What to do after apply."
  value = <<-EOT

    Node provisioning has started. cloud-init is running setup-aws.sh on
    the box now (Docker + Solana CLI + build + Caddy). Give it a few minutes.

    1. DNS:
    %{~ if var.route53_zone_id != "" ~}
       Route 53 A record for ${var.domain} -> ${aws_eip.tribe.public_ip} created.
    %{~ else ~}
       Create an A record:  ${var.domain}  ->  ${aws_eip.tribe.public_ip}
       Caddy will issue the TLS cert automatically once it resolves.
    %{~ endif ~}

    2. Watch the bootstrap:
       ssh ubuntu@${aws_eip.tribe.public_ip}
       sudo tail -f /var/log/tribe-setup.log

    3. Verify (after DNS + cert, ~1-2 min):
       curl https://${var.domain}/health
       curl https://${var.domain}:3003/health

    4. Point clients at it:
       tribe seed set wss://${var.domain}/gossip
       tribe-twitter-app link https://${var.domain}

    NOTE: the ER server wallet is funded by a one-time devnet airdrop. If
    it didn't land, top it up (see deploy/prod/README.md § wallet).
  EOT
}

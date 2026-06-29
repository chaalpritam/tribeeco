# TribeEco protocol node on Google Cloud

A public Google Cloud node for the TribeEco gossip mesh. This runs the
protocol backend pieces that home hubs need in order to find each other:

- `hub` on `https://$DOMAIN`
- hub gossip on `wss://$DOMAIN/gossip`
- ER server on `https://$DOMAIN:3003`
- Postgres databases in Docker volumes on the VM boot disk
- Caddy for automatic Let's Encrypt TLS

Home Mac minis still run `tribe start` locally. They connect outbound to
the Google Cloud node, so they do not need public IPs or router port
forwarding.

## Topology

```text
Mac mini hub A ─┐
Mac mini hub B ─┼── wss://seed.example.com/gossip ── Google Cloud hub
Mac mini hub C ─┘                                      │
                                                       └── ER server :3003
```

The Google node can also peer with other public seed nodes via `PEERS`,
so multiple GCP/AWS/VPS seeds form one shared mesh.

## Provision With Terraform

Prereqs:

- A Google Cloud project with billing enabled.
- `gcloud auth application-default login`
- Terraform installed.
- A domain or subdomain you can point at the VM static IP.

```bash
cd deploy/gcp/terraform
cp terraform.tfvars.example terraform.tfvars
# edit project_id, zone, domain, ssh_allowed_ranges, postgres_password
terraform init
terraform apply
```

After apply, point your DNS `A` record at:

```bash
terraform output static_ip
```

If you use Cloud DNS, set `dns_managed_zone` in `terraform.tfvars` and
Terraform will create the `A` record for you.

Wait until DNS resolves:

```bash
dig +short seed.example.com
```

Then watch first boot:

```bash
gcloud compute ssh tribe-gcp \
  --zone "$(terraform output -raw zone)" \
  --command "sudo tail -f /var/log/tribe-gcp-setup.log"
```

## Verify

```bash
curl https://seed.example.com/health
curl https://seed.example.com:3003/health
```

From each Mac mini:

```bash
tribe seed set wss://seed.example.com/gossip
tribe stop
tribe start
tribe peers
```

`tribe peers` should show the Google hub id, defaulting to `seed-gcp-1`.

## Manual Install On An Existing VM

Create an Ubuntu 22.04+ VM, open ingress TCP `80`, `443`, and `3003`,
point DNS at it, then run:

```bash
DOMAIN=seed.example.com bash <(curl -fsSL \
  https://raw.githubusercontent.com/chaalpritam/TribeEco/master/deploy/gcp/setup-gcp.sh)
```

Optional environment:

```bash
HUB_ID=seed-gcp-2
POSTGRES_PASSWORD=change-me
SOLANA_RPC_URL=https://api.devnet.solana.com
SOLANA_WS_URL=wss://api.devnet.solana.com
PEERS=wss://seed.tribeprotocol.xyz/gossip
```

## Operations

```bash
cd /opt/tribe-gcp/deploy/gcp

# logs
sudo docker compose -f docker-compose.gcp.yml logs -f hub er-server
sudo docker compose -f docker-compose.gcp.yml logs -f caddy

# restart
sudo DOMAIN=seed.example.com docker compose -f docker-compose.gcp.yml restart

# update
cd /opt/tribe-gcp
sudo git pull
sudo git submodule update --init --recursive
cd deploy/gcp
sudo DOMAIN=seed.example.com docker compose -f docker-compose.gcp.yml up -d --build
```

## Notes

- Port `4000` is not exposed publicly. Caddy terminates TLS and proxies
  to the hub on the internal Docker network.
- Port `3003` is exposed with TLS because `tribe-app link` and the
  native clients derive the ER URL as `<hub-host>:3003`.
- The ER server wallet is generated at
  `/opt/tribe-gcp/deploy/gcp/server-wallet.json`. It is a private key:
  back it up and never commit it.
- Public Solana devnet RPC is rate-limited. For a real public seed,
  set `SOLANA_RPC_URL` and `SOLANA_WS_URL` to a dedicated provider.


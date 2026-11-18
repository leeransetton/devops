# DNS records that point a hostname at the cluster.
#
# EDIT THIS when a project's hostname should be served by the cluster:
#   zone => list of record names, "@" for the bare domain. The zone must be in var.domains.
# Only names listed here are touched; everything else in the zones (records for the old
# droplet "main", MX, TXT...) is left alone. Before switching a name that already has an
# A record, import that record first (see CLAUDE.md, "Point a hostname at the cluster").
locals {
  cluster_hosts = {
    # "leeransetton.com" = ["@", "www"]
    # "gamadanak.com"    = ["setton"]
  }
}

locals {
  cluster_records = merge([
    for zone, names in local.cluster_hosts : {
      for n in names : "${n == "@" ? "" : "${n}."}${zone}" => { zone = zone, name = n }
    }
  ]...)
}

# The load balancer is created by Traefik (Service annotation do-loadbalancer-name = var.name),
# so it's read here rather than managed.
data "digitalocean_loadbalancer" "ingress" {
  count = length(local.cluster_records) > 0 ? 1 : 0
  name  = var.name
}

resource "digitalocean_record" "cluster" {
  for_each = local.cluster_records

  domain = digitalocean_domain.this[each.value.zone].id
  type   = "A"
  name   = each.value.name
  value  = data.digitalocean_loadbalancer.ingress[0].ip
  ttl    = 300
}

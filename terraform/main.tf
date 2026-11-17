provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_kubernetes_versions" "current" {}

resource "digitalocean_vpc" "main" {
  name     = "${var.name}-vpc"
  region   = var.region
  ip_range = "10.10.0.0/20"
}

resource "digitalocean_kubernetes_cluster" "main" {
  name     = var.name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.current.latest_version
  vpc_uuid = digitalocean_vpc.main.id

  # Free control plane. Set to true for the ~$40/mo HA control plane.
  ha = false

  # DigitalOcean applies patch upgrades in the maintenance window.
  # surge_upgrade adds a temporary node during upgrades so the single node can drain.
  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = "sunday"
    start_time = "02:00"
  }

  node_pool {
    name       = "default"
    size       = var.node_size
    auto_scale = true
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
  }

  lifecycle {
    # Upgrades are handled by auto_upgrade; don't fight them on every plan.
    ignore_changes = [version]
  }
}

resource "digitalocean_domain" "this" {
  for_each = toset(var.domains)
  name     = each.value
}

resource "digitalocean_project" "main" {
  name        = var.name
  purpose     = "Web Application"
  environment = "Production"
  resources = concat(
    [digitalocean_kubernetes_cluster.main.urn],
    [for d in digitalocean_domain.this : d.urn],
  )
}

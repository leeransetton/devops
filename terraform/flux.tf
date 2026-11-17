locals {
  kube = {
    host                   = digitalocean_kubernetes_cluster.main.endpoint
    token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = local.kube.host
  token                  = local.kube.token
  cluster_ca_certificate = local.kube.cluster_ca_certificate
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

# Flux pushes to the repo (image tag bumps), so its deploy key needs write access.
resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.name}"
  repository = var.github_repo
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false
}

provider "flux" {
  kubernetes = local.kube
  git = {
    url    = "ssh://git@github.com/${var.github_owner}/${var.github_repo}.git"
    branch = "main"
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.flux]

  embedded_manifests = true
  path               = "clusters/prod"
  components_extra   = ["image-reflector-controller", "image-automation-controller"]
}

# Key Flux uses to decrypt *.sops.yaml files.
resource "kubernetes_secret" "sops_age" {
  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }
  data = {
    "age.agekey" = var.sops_age_key
  }
}

# external-dns namespace and token are owned here so no secret has to be committed.
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_secret" "external_dns" {
  metadata {
    name      = "external-dns-digitalocean"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }
  data = {
    token = var.external_dns_token
  }
}

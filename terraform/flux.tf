provider "github" {
  owner = var.github_owner
  token = var.github_token
}

# Flux pushes to the repo (image tag bumps), so its deploy key needs write access.
# The key pair is created once with ssh-keygen (see README) and stays outside git.
resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.name}"
  repository = var.github_repo
  key        = trimspace(file("${var.flux_ssh_key_file}.pub"))
  read_only  = false
}

provider "flux" {
  kubernetes = {
    host                   = digitalocean_kubernetes_cluster.main.endpoint
    token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
  git = {
    url    = "ssh://git@github.com/${var.github_owner}/${var.github_repo}.git"
    branch = "main"
    ssh = {
      username    = "git"
      private_key = file(var.flux_ssh_key_file)
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.flux]

  embedded_manifests = true
  path               = "clusters/prod"
  components_extra   = ["image-reflector-controller", "image-automation-controller"]
}

# Secret the cluster needs that must never be in git:
#   flux-system/sops-age - key Flux uses to decrypt *.sops.yaml
# Created with kubectl instead of the kubernetes provider, because Windows Smart App
# Control blocks that provider's binary on the owner's machine. Re-runs when any input changes.
resource "terraform_data" "cluster_secrets" {
  depends_on = [flux_bootstrap_git.this]

  triggers_replace = {
    cluster = digitalocean_kubernetes_cluster.main.id
    age_key = sha256(file(var.sops_age_key_file))
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-NonInteractive", "-Command"]
    environment = {
      KUBECONFIG_RAW = digitalocean_kubernetes_cluster.main.kube_config[0].raw_config
      AGE_KEY_FILE   = var.sops_age_key_file
    }
    command = <<-EOT
      $ErrorActionPreference = 'Stop'
      $kc = New-TemporaryFile
      try {
        [IO.File]::WriteAllText($kc, $env:KUBECONFIG_RAW)
        function Apply-Yaml([string[]]$yaml) {
          $yaml | kubectl --kubeconfig $kc apply -f -
          if ($LASTEXITCODE -ne 0) { throw 'kubectl apply failed' }
        }
        Apply-Yaml (kubectl -n flux-system create secret generic sops-age "--from-file=age.agekey=$env:AGE_KEY_FILE" --dry-run=client -o yaml)
      } finally {
        Remove-Item $kc -Force -ErrorAction SilentlyContinue
      }
    EOT
  }
}

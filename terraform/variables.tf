variable "do_token" {
  description = "DigitalOcean API token used by OpenTofu."
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub token that can add a deploy key to the devops repo (fine-grained PAT: Administration + Contents read/write on that repo)."
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub user or org that owns the devops repo."
  type        = string
}

variable "github_repo" {
  description = "Name of this repo on GitHub."
  type        = string
  default     = "devops"
}

variable "name" {
  description = "Name used for the cluster, VPC, load balancer and DO project."
  type        = string
  default     = "side-projects"
}

variable "region" {
  description = "DigitalOcean region. fra1 (Frankfurt) is the closest DOKS region to Israel."
  type        = string
  default     = "fra1"
}

variable "node_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 3
}

variable "domains" {
  description = "DNS zones managed in DigitalOcean. Records inside them are created by external-dns."
  type        = list(string)
  default = [
    "leeransetton.com",
    "sqloutputtojson.com",
    "gamadanak.com",
  ]
}

variable "flux_ssh_key_file" {
  description = "Path to the private SSH key Flux uses for the repo (public key at the same path + .pub). Create with: ssh-keygen -t ed25519 -N \"\" -f <path>"
  type        = string
}

variable "sops_age_key_file" {
  description = "Path to the age private key file Flux uses to decrypt *.sops.yaml secrets."
  type        = string
}

variable "external_dns_token" {
  description = "DigitalOcean token for external-dns. Use a custom-scoped token with domain read/write only."
  type        = string
  sensitive   = true
}

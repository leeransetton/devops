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
    "elizabethsetton.com",
    "sqloutputtojson.com",
    "gamadanak.com",
  ]
}

variable "sops_age_key" {
  description = "Contents of the age private key file Flux uses to decrypt *.sops.yaml secrets."
  type        = string
  sensitive   = true
}

variable "external_dns_token" {
  description = "DigitalOcean token for external-dns. Use a custom-scoped token with domain read/write only."
  type        = string
  sensitive   = true
}

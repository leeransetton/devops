output "cluster_id" {
  value = digitalocean_kubernetes_cluster.main.id
}

output "kubeconfig_command" {
  description = "Run this to get a kubeconfig for kubectl."
  value       = "doctl kubernetes cluster kubeconfig save ${digitalocean_kubernetes_cluster.main.id}"
}

output "nameservers" {
  description = "Point each domain at these nameservers at your registrar."
  value       = ["ns1.digitalocean.com", "ns2.digitalocean.com", "ns3.digitalocean.com"]
}

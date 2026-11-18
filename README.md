# devops

Everything that runs in DigitalOcean for my side projects: one Kubernetes cluster in Frankfurt (`fra1`), shared by independent projects.

- **`terraform/`**: OpenTofu for resources outside the cluster: VPC, cluster, node pool, DNS zones, DO project, and the Flux install.
- **`clusters/prod/`**: Flux entrypoint. Applies `infrastructure/controllers` → `infrastructure/configs` → `apps`.
- **`infrastructure/`**: Traefik (single load balancer), cert-manager (Let's Encrypt), metrics-server (HPA). DNS records live in `terraform/dns.tf`.
- **`charts/web-app/`**: one Helm chart used by every project.
- **`apps/<project>/`**: one folder per project. `values.yaml` holds everything you normally change.

Push to `main` → Flux applies it within a minute or two.

## Everyday tasks

| Task | How |
|---|---|
| Add a project | Add the CI pipeline to the app repo, then `./scripts/new-project.sh <name> <host> <owner>/<repo> <port>`. Full steps: `CLAUDE.md` → "Add a project". |
| Change HPA | Edit `hpa.min` / `hpa.max` / `hpa.cpu` in `apps/<name>/values.yaml`, push. |
| Add a volume | Add an entry under `volumes:` in `values.yaml`. To grow it, raise `size`. Volumes force a single replica. |
| Deploy a new version | Push to the app repo. Its workflow (`docs/app-repo-release.yml`) pushes an image; Flux commits the new tag here and rolls it out. |
| Add an env secret | See "Secrets" below. |
| More capacity | Change `node_size` / `max_nodes` in `terraform.tfvars`, `tofu plan`, `tofu apply`. |

Useful commands:

```sh
flux get all -A                     # status of everything Flux manages
flux reconcile kustomization apps --with-source   # don't wait for the interval
kubectl top pods -A                 # real memory/CPU usage
```

## First-time setup

Tools: `tofu`, `doctl`, `kubectl`, `flux`, `sops`, `age`.

1. **GitHub repo.** Create `devops` on GitHub, push this folder to `main`.
2. **State bucket.** In the DO console create a Spaces bucket in `fra1` (e.g. `<you>-tfstate`) and a Spaces access key. Copy `terraform/backend.hcl.example` to `terraform/backend.hcl` and fill it in.
3. **Tokens.**
   - DO API token with full access → `do_token`.
   - GitHub fine-grained PAT for the `devops` repo with **Administration** and **Contents** read/write → `github_token`.
4. **SOPS key.** `age-keygen -o %APPDATA%\sops\age\keys.txt` (sops finds it there automatically). Put the public key (`age1...`) in `.sops.yaml`, set `sops_age_key_file` to the file's path, and back the file up in a password manager.
   **Flux deploy key.** `ssh-keygen -t ed25519 -N "" -f %USERPROFILE%\.ssh\flux-devops`, and set `flux_ssh_key_file` to that path.
5. **Variables.** Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill it in.
6. **Domains already in DigitalOcean?** Import them instead of creating them:
   ```sh
   tofu import 'digitalocean_domain.this["leeransetton.com"]' leeransetton.com
   ```
   Domains hosted elsewhere: after apply, set the registrar's nameservers to `ns1/ns2/ns3.digitalocean.com`, and re-create any existing records you still need (MX, TXT for email) in DigitalOcean first.
7. **Apply.**
   ```sh
   cd terraform
   tofu init -backend-config=backend.hcl
   tofu apply
   ```
   Flux commits its own manifests to `clusters/prod/flux-system/`. Run `git pull` afterwards.
8. **Kubeconfig.** `doctl kubernetes cluster kubeconfig save side-projects`, then `flux get all -A` until everything is Ready.
9. **metrics-server.** If DOKS already ships one (`kubectl get deploy -n kube-system metrics-server` before Flux installs ours), remove `infrastructure/controllers/metrics-server.yaml`.
10. **Pin chart versions.** The infrastructure HelmReleases use open version ranges so the first install finds a current release. Once Ready, run `flux get helmreleases -A` and pin each `version:` to what was installed.

## Secrets

App env vars:

```sh
kubectl create secret generic <name>-env -n <name> \
  --from-literal=API_KEY=... --dry-run=client -o yaml > apps/<name>/secrets.sops.yaml
sops -e -i apps/<name>/secrets.sops.yaml
```

Then uncomment `secrets.sops.yaml` in `apps/<name>/kustomization.yaml` and set `envFromSecret: <name>-env` in `values.yaml`.

Image pull credentials (private GHCR): one classic PAT with `read:packages`, managed by `scripts/ghcr-pull.sh`. See `CLAUDE.md` → "Rotate the GHCR pull token".

## App repos

Copy `docs/app-repo-release.yml` into each app repo as `.github/workflows/release.yml`. It builds on PRs, pushes `ghcr.io/<owner>/<repo>:main-<sha>-<timestamp>` on `main`, and keeps only the 10 newest images.

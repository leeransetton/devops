# Agent guide: devops repo

This repo is the single source of truth for everything in DigitalOcean. The owner does not run manual steps: you make the change in git, push to `main`, and verify it. Read this whole file before changing anything.

## How the system works

- **OpenTofu (`terraform/`)** owns resources outside the cluster: VPC, the DOKS cluster `side-projects` in `fra1`, its single autoscaling node pool, the DNS zones, the DO project, the Flux install, and two in-cluster secrets (`flux-system/sops-age`, `external-dns/external-dns-digitalocean`). State is in a Spaces bucket.
- **Flux** watches `main` of `github.com/leeransetton/devops`, path `clusters/prod`. It applies `infrastructure/controllers` → `infrastructure/configs` → `apps`, in that order. Anything changed by hand in the cluster is reverted.
- **Traefik** is the only ingress and owns the only load balancer. **cert-manager** issues Let's Encrypt certs (ClusterIssuer `letsencrypt`). **external-dns** creates DNS records from Ingress hosts in the zones listed in `infrastructure/controllers/external-dns.yaml`.
- **Every project** is `apps/<name>/`, deployed by the shared chart `charts/web-app/`. Projects are independent and isolated by NetworkPolicy; never make one depend on another.
- **Image updates are automatic.** App repos push `ghcr.io/<owner>/<repo>:main-<sha7>-<unixts>`; Flux's ImagePolicy picks the newest and commits the tag into `apps/<name>/values.yaml`. Expect commits from `fluxcdbot` on `main`; always `git pull --rebase` before you start and before you push.

## Rules

1. **Change git, not the cluster.** Never `kubectl apply/edit/delete/scale` to make a lasting change; Flux reverts it. `kubectl` is for reading and debugging only. The exceptions are `flux reconcile ...` and deleting a stuck pod.
2. **Never commit plaintext secrets.** Secrets go in `*.sops.yaml` encrypted with `sops -e -i`. Before committing, check that every `*.sops.yaml` file contains a `sops:` block. Never commit `*.tfvars`, `backend.hcl`, `*.agekey`, or kubeconfigs (they're in `.gitignore`; don't weaken it).
3. **OpenTofu changes cost money or can destroy things.** Always run `tofu plan` and show the owner a summary first. Get explicit approval before `tofu apply` if the plan creates billable resources, replaces or destroys anything, or touches the cluster or node pool. Never run `tofu destroy`.
4. **Keep it lean.** One node, one load balancer. Don't add a new load balancer (`type: LoadBalancer` Service), a service mesh, a monitoring stack or other platform components without asking. Prefer changing `values.yaml` over adding raw manifests.
5. **Don't edit `clusters/prod/flux-system/`.** Flux generates it.
6. **Don't touch the `$imagepolicy` comments** in `values.yaml`, and don't hand-edit `image.tag` unless the owner asks for a rollback or pin (see below).
7. **Stay within the namespace quota** (`apps/_template/namespace.yaml`: 500m CPU requests, 768Mi memory requests, 1536Mi memory limits, 3 PVCs, 20Gi storage). `requests × hpa.max` must fit. If a change needs more, raise that project's quota in its `namespace.yaml` and say so.
8. **Commit style:** small commits, imperative subject with a scope, e.g. `apps/gamadanak: raise hpa max to 4`. Push to `main` directly unless the owner asks for a PR.

## Recipes

### Add a project

Ask the owner for anything you don't know: **name** (lowercase, dashes ok; it becomes the namespace), **hostnames**, **app repo** (`owner/repo`), **container port**, **health path**, whether the image is **public or private**, env vars, and whether it needs a volume.

1. `./scripts/new-project.sh <name> <host> ghcr.io/<owner>/<repo> <port>` (image names must be lowercase). This copies `apps/_template`, replaces the placeholders, and registers the project in `apps/kustomization.yaml`.
2. Edit `apps/<name>/values.yaml`: extra `hosts` (e.g. `www.` variant), `healthPath`, `env`, `resources`, `hpa`, `volumes`.
3. Every host must be inside a zone in `variables.tf` → `domains` **and** in `domainFilters` in `infrastructure/controllers/external-dns.yaml`. If it's a new domain, add it to both. This needs a `tofu apply` (rule 3), and the owner must point the domain's nameservers at `ns1/ns2/ns3.digitalocean.com`.
4. Private image: see "Secrets" in `README.md` (`ghcr-pull` in the project namespace and in `flux-system`).
5. App repo: make sure it has `.github/workflows/release.yml` copied from `docs/app-repo-release.yml`. If you have access to the app repo, add it there; otherwise tell the owner it's needed. Until the first image is pushed, `image.tag` stays `replace-me` and the pod shows `ImagePullBackOff`. That's expected.
6. Commit, push, verify (below).

### Change HPA, resources, env, hostnames

Edit `apps/<name>/values.yaml` only. The chart's options are documented in `charts/web-app/values.yaml`. The ConfigMap is watched, so Flux rolls it out right after the `apps` Kustomization applies.

### Add or resize a volume

Add an entry under `volumes:` (`name`, `size`, `mountPath`) in `values.yaml`. Volumes are DigitalOcean block storage, ReadWriteOnce: the chart then forces one replica, disables HPA, and uses the Recreate strategy, so the project has a few seconds of downtime on each deploy. To resize, increase `size` (shrinking isn't possible). PVCs are kept if a project is removed; deleting the data needs the owner's explicit approval.

### Add or change an app secret

```sh
kubectl create secret generic <name>-env -n <name> --from-literal=KEY=value \
  --dry-run=client -o yaml > apps/<name>/secrets.sops.yaml
sops -e -i apps/<name>/secrets.sops.yaml
```

Make sure `secrets.sops.yaml` is listed in `apps/<name>/kustomization.yaml` and `envFromSecret: <name>-env` is set in `values.yaml`. To change one value: `sops apps/<name>/secrets.sops.yaml` needs an editor, so instead decrypt to stdout, regenerate the file with all keys, and re-encrypt. Get secret values from the owner; never invent them or echo them back in chat.

### Roll back or pin a version

Set `image.tag` in `values.yaml` to the wanted tag and **remove** the `# {"$imagepolicy": ...:tag}` comment on that line, otherwise Flux moves it forward again. To unpin, restore the comment exactly as in `apps/_template/values.yaml`.

### Remove a project

Delete `apps/<name>/` and its line in `apps/kustomization.yaml`. Flux prunes everything, and external-dns removes the DNS records. Any PVC is kept (`helm.sh/resource-policy: keep`); mention it to the owner.

### Change cluster capacity

Edit `terraform/terraform.tfvars` (`node_size`, `min_nodes`, `max_nodes`) or `variables.tf` defaults, then `tofu plan` → owner approval → `tofu apply`. Changing `node_size` replaces the node pool.

### Change a platform component (Traefik, cert-manager, external-dns, metrics-server)

Edit its HelmRelease in `infrastructure/controllers/`. Pin `version:` to exact versions; when bumping, read the chart's release notes for breaking changes first.

## Verify every change

After pushing:

```sh
flux reconcile kustomization flux-system --with-source
flux get kustomizations                      # all Ready=True
flux get helmreleases -A                     # the touched release Ready=True
kubectl -n <name> get pods,ingress,hpa,pvc,certificate
curl -sI https://<host>                      # once DNS and cert are ready
```

- A new cert can take a few minutes. `kubectl -n <name> describe certificate` shows why one is stuck.
- If a reconcile fails, read `flux logs --level=error` and `kubectl -n <name> describe helmrelease <name>`, fix it in git, and push again. Don't patch the cluster.
- Report to the owner what changed and what you verified, and say plainly if something isn't Ready yet.

## Local validation before pushing

```sh
kubectl kustomize apps >/dev/null
kubectl kustomize infrastructure/controllers >/dev/null
helm template x charts/web-app -f apps/<name>/values.yaml >/dev/null
(cd terraform && tofu fmt -check -recursive && tofu validate)
```

CI (`.github/workflows/validate.yml`) runs the same checks on every push.

## Windows quirks on the owner's machine

- **Smart App Control blocks unsigned provider binaries with no download reputation.** `hashicorp/kubernetes` and `hashicorp/tls` are blocked ("An Application Control policy has blocked this file"). `digitalocean`, `fluxcd/flux` and `integrations/github` work. Don't add new OpenTofu providers without testing that their binary runs. Use `terraform_data` + `local-exec` with `kubectl` (see `terraform/flux.tf`) for in-cluster bits instead.
- **Norton 360 intercepts TLS**, which breaks OpenTofu's local plugin handshake (`x509: certificate signed by unknown authority`). Always run `tofu` with `TF_DISABLE_PLUGIN_TLS=1` (traffic is localhost only) and outside the Claude Code sandbox.
- `clusters/prod` has no `kustomization.yaml` on purpose (Flux generates one), so `kubectl kustomize clusters/prod` fails locally. That's expected.
- **winget:** pass `--source winget`; the msstore source fails on this machine.

## Access

Credentials live only on the owner's machine: `terraform/terraform.tfvars`, `terraform/backend.hcl`, the kubeconfig from `doctl kubernetes cluster kubeconfig save side-projects`, and the age key (`SOPS_AGE_KEY_FILE`). If one is missing, stop and ask the owner. Don't try to work around it.

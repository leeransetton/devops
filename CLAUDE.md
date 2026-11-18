# Agent guide: devops repo

This repo is the single source of truth for everything in DigitalOcean. The owner does not run manual steps: you make the change in git, push to `main`, and verify it. Read this whole file before changing anything.

## How the system works

- **OpenTofu (`terraform/`)** owns resources outside the cluster: VPC, the DOKS cluster `side-projects` in `fra1`, its single autoscaling node pool, the DNS zones, the DO project, the Flux install, the in-cluster secret `flux-system/sops-age`, and the **DNS records that point hostnames at the cluster** (`terraform/dns.tf`). State is in the versioned Spaces bucket `leeransetton-tfstate` (fra1).
- **Flux** watches `main` of `github.com/leeransetton/devops`, path `clusters/prod`. It applies `infrastructure/controllers` → `infrastructure/configs` → `apps`, in that order. Anything changed by hand in the cluster is reverted.
- **Traefik** is the only ingress and owns the only load balancer. **cert-manager** issues Let's Encrypt certs (ClusterIssuer `letsencrypt`) over HTTP-01, so a cert is only issued once the hostname's DNS points at the load balancer. There is **no external-dns**: its DigitalOcean provider was removed upstream, so DNS records are managed in OpenTofu instead.
- **Before this cluster**, the sites ran on the droplet `main` (167.71.61.75, fra1). DNS for `leeransetton.com`, `sqloutputtojson.com` and `setton.gamadanak.com` still points there until each project is moved. Don't change or delete those records or the droplet without the owner's approval.
- **Every project** is `apps/<name>/`, deployed by the shared chart `charts/web-app/`. Projects are independent and isolated by NetworkPolicy; never make one depend on another.
- **Images live in GitHub Container Registry (GHCR)**, private, one package per app repo: `ghcr.io/<owner>/<repo>` (lowercase). Each app repo's CI (`.github/workflows/release.yml`, copied from `docs/app-repo-release.yml`) builds on PRs, and on `main` pushes `main-<sha7>-<unixts>` and then deletes all but the **10 newest** versions (retention). GHCR storage is currently free, but GitHub may start billing with a month's notice, so retention stays on.
- **Image updates are automatic.** Flux's ImageRepository/ImagePolicy (`apps/<name>/image.yaml`) sees the newest tag and commits it into `apps/<name>/values.yaml`. Expect commits from `fluxcdbot` on `main`; always `git pull --rebase` before you start and before you push.
- **Pulling private images:** one GitHub classic PAT (`read:packages` only) is stored as the SOPS secret `ghcr-pull`, once in `flux-system` (`infrastructure/configs/ghcr-pull.sops.yaml`, for listing tags) and once per project namespace (`apps/<name>/ghcr-pull.sops.yaml`, for kubelet pulls). `scripts/ghcr-pull.sh` manages both.

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

Ask the owner for anything you don't know: **name** (lowercase, dashes ok; it becomes the namespace), **hostnames**, **app repo** (`owner/repo`), **container port**, **health path**, env vars/secrets, and **whether it needs persistent storage** (what path, how much, does the app run as non-root).

**A. CI pipeline in the app repo** (do this first, so an image exists before deploying):

1. Clone the app repo next to this one (`gh repo clone <owner>/<repo> ../<repo>`), branch from its default branch.
2. **Dockerfile:** the repo needs one at its root that builds a production image listening on the agreed port. If it's missing, write one that fits the stack (multi-stage, small runtime base, run as a non-root user where practical) and build it locally if Docker is available. Show it to the owner.
3. Copy `docs/app-repo-release.yml` to `.github/workflows/release.yml`. Adjust only `context`/`file` if the Dockerfile isn't at the root, and `KEEP_VERSIONS` if the owner wants a different rollback window.
4. If the app repo's default branch isn't `main`, change `branches: [main]` in the workflow. Tags stay `main-...`, because the ImagePolicy matches that prefix.
5. Commit and push (owner approves pushes to app repos too). Watch the run: `gh run watch -R <owner>/<repo>`. The first push to `main` creates the GHCR package `ghcr.io/<owner>/<repo>`, private and linked to the repo, which lets the cleanup job delete old versions with the built-in token.
6. Confirm the image exists: `gh api /user/packages/container/<repo>/versions --jq '.[0].metadata.container.tags'`.

**B. Deploy it from this repo:**

1. `./scripts/new-project.sh <name> <host> <owner>/<repo> <port>`. This copies `apps/_template`, sets the image to `ghcr.io/<owner>/<repo>` (lowercased), registers the project in `apps/kustomization.yaml`, and writes the encrypted pull secret `apps/<name>/ghcr-pull.sops.yaml`. Kubernetes pulls with it via `imagePullSecrets: [ghcr-pull]`, and Flux reads tags via `secretRef: ghcr-pull` in `image.yaml`.
2. Edit `apps/<name>/values.yaml`: extra `hosts` (e.g. `www.` variant), `healthPath`, `env`, `resources`, `hpa`, and `volumes`/`podSecurityContext` (see "Add or resize a volume").
3. Every host must be inside a zone listed in `terraform/variables.tf` → `domains`. A new domain needs adding there (a `tofu apply`, rule 3), and the owner must point its nameservers at `ns1/ns2/ns3.digitalocean.com`.
4. Commit and push, then verify (below). Within ~5 minutes Flux replaces `image.tag: replace-me` with the newest tag (a `fluxcdbot` commit), and the pod starts. `flux get images all -A` shows what Flux sees.
5. Once the pod is Running and healthy, do "Point a hostname at the cluster" below. Never earlier, so live traffic isn't cut over to a broken app.

### Point a hostname at the cluster (DNS)

DNS records are in `terraform/dns.tf` → `local.cluster_hosts` (zone → list of names, `@` = bare domain). Each name becomes an A record to the load balancer `side-projects`.

1. Check the zone's current records: `doctl compute domain records list <zone>`.
2. If the name already has an A record (e.g. pointing at the old droplet), add an `import` block to `terraform/imports.tf` so OpenTofu takes over that record and changes it in place. That avoids a duplicate A record and any gap in service:
   ```hcl
   import {
     to = digitalocean_record.cluster["www.leeransetton.com"]   # key: "<name>.<zone>", or "<zone>" for "@"
     id = "leeransetton.com,<record id from doctl>"
   }
   ```
3. Add the name to `local.cluster_hosts`, then run `tofu plan` (from `terraform/`, see "Windows quirks"). The plan must show only the expected record imports/changes. Show it to the owner and apply after approval.
4. Verify: `nslookup <host> 8.8.8.8` returns the load balancer IP, then `kubectl -n <name> get certificate` turns Ready, then `curl -sI https://<host>`.

Removing a name from `cluster_hosts` deletes that record.

### Change HPA, resources, env, hostnames

Edit `apps/<name>/values.yaml` only. The chart's options are documented in `charts/web-app/values.yaml`. The ConfigMap is watched, so Flux rolls it out right after the `apps` Kustomization applies.

### Add or resize a volume (persistent storage)

Add an entry under `volumes:` in `values.yaml`:

```yaml
volumes:
  - name: data        # PVC becomes <project>-data
    size: 1Gi         # minimum 1Gi; $0.10/GB-month
    mountPath: /data  # where the app writes
podSecurityContext:
  fsGroup: 1000       # only if the container runs as non-root: its group id, so it can write
```

How it behaves:
- **DigitalOcean block storage, ReadWriteOnce.** A volume attaches to one node at a time, so the chart forces **1 replica**, **disables HPA**, and uses the **Recreate** strategy: a few seconds of downtime per deploy. If a project needs to scale out, keep its state in a database instead of on a volume.
- **Storage class `do-block-storage-retain`** (chart default): deleting the PVC or the project keeps the DO volume and its data. The PVC also has `helm.sh/resource-policy: keep`. Use `storageClass: do-block-storage-xfs-retain` only if the app needs XFS.
- **Resize:** increase `size` and push; it expands online. Shrinking is impossible.
- **Limits:** quota per project is 3 PVCs / 20Gi (`namespace.yaml`), and each node can attach 15 volumes.
- **Write the app for it:** everything that must survive a restart goes under `mountPath`; the rest of the container filesystem is lost on every deploy.
- **Backups:** volumes are not backed up automatically. Before risky changes, take a snapshot with `doctl compute volume snapshot <volume-id> --snapshot-name <project>-<date>` (`kubectl get pv` shows the volume id as `volumeHandle`). If the owner wants scheduled backups, propose a design first; don't add a component without asking.
- **Deleting data** (removing a PVC, deleting a retained DO volume, deleting snapshots) always needs the owner's explicit approval.

### Add or change an app secret

```sh
kubectl create secret generic <name>-env -n <name> --from-literal=KEY=value \
  --dry-run=client -o yaml > apps/<name>/secrets.sops.yaml
sops -e -i apps/<name>/secrets.sops.yaml
```

Make sure `secrets.sops.yaml` is listed in `apps/<name>/kustomization.yaml` and `envFromSecret: <name>-env` is set in `values.yaml`. To change one value: `sops apps/<name>/secrets.sops.yaml` needs an editor, so instead decrypt to stdout, regenerate the file with all keys, and re-encrypt. Get secret values from the owner; never invent them or echo them back in chat.

### Roll back or pin a version

Set `image.tag` in `values.yaml` to the wanted tag and **remove** the `# {"$imagepolicy": ...:tag}` comment on that line, otherwise Flux moves it forward again. To unpin, restore the comment exactly as in `apps/_template/values.yaml`.

Only the 10 newest images exist (CI retention), so you can roll back at most 9 deploys. While a project is pinned, warn the owner that 10 more pushes to the app repo would delete the pinned image. Raise `KEEP_VERSIONS` in that app's workflow if the pin must last.

### Rotate the GHCR pull token

The owner creates a new classic PAT (scope `read:packages` only) at https://github.com/settings/tokens and saves it in `ghcr-token.txt` at the repo root (git-ignored). Then:

```sh
./scripts/ghcr-pull.sh init ghcr-token.txt   # re-encrypts the flux-system copy and every apps/*/ copy
rm ghcr-token.txt
```

Commit and push, then check `flux get images repository -A` is Ready. If the old token is still valid, ask the owner to revoke it.

### Remove a project

Delete `apps/<name>/` and its line in `apps/kustomization.yaml`; Flux prunes everything. Remove its names from `local.cluster_hosts` in `terraform/dns.tf` (a `tofu apply`, rule 3). Volumes are kept (retain class, and the PVC has `helm.sh/resource-policy: keep`); tell the owner they still cost money and ask before deleting them. The app repo's GHCR package and CI are untouched; ask the owner whether to delete them.

### Change cluster capacity

Edit `terraform/terraform.tfvars` (`node_size`, `min_nodes`, `max_nodes`) or `variables.tf` defaults, then `tofu plan` → owner approval → `tofu apply`. Changing `node_size` replaces the node pool.

### Change a platform component (Traefik, cert-manager, metrics-server)

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

Credentials live only on the owner's machine: `terraform/terraform.tfvars`, `terraform/backend.hcl`, the age key (`%APPDATA%/sops/age/keys.txt`, found by sops automatically), `doctl` (logged in via `doctl auth init`), the kubeconfig (`~/.kube/config`, context `do-fra1-side-projects`), and `gh` (logged in as `leeransetton`, can push to the owner's repos). Tools are installed with winget; a shell started before an install may need the full path (`C:/Program Files/GitHub CLI/gh.exe`, `%LOCALAPPDATA%/Microsoft/WinGet/Packages/...`). If a credential or tool is missing, tell the owner and offer to install or set it up; don't work around it.

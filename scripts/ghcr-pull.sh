#!/usr/bin/env bash
# Manage the GHCR pull secret (encrypted with SOPS).
#
#   ./scripts/ghcr-pull.sh init <token-file>   create/rotate the shared secret from a classic PAT
#                                               (scope read:packages), then refresh every project's copy
#   ./scripts/ghcr-pull.sh project <name>      write apps/<name>/ghcr-pull.sops.yaml from the shared secret
#
# The shared secret lives in infrastructure/configs/ghcr-pull.sops.yaml (namespace flux-system,
# used by Flux to list image tags). Each project gets a copy in its own namespace (used by kubelet
# to pull the image).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shared="infrastructure/configs/ghcr-pull.sops.yaml"
owner="leeransetton"

# Tools installed by winget may not be on PATH in older shells.
for d in /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/{Kubernetes.kubectl,SecretsOPerationS.SOPS}_*; do
  [[ -d "$d" ]] && PATH="$PATH:$d"
done
command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }
command -v sops >/dev/null || { echo "sops not found" >&2; exit 1; }

encrypt_to() { # <namespace> <dest>; plaintext YAML on stdin
  local ns="$1" dest="$2"
  sed -E "s/^([[:space:]]*namespace:).*/\1 $ns/" > "$dest"
  if ! sops -e -i "$dest"; then rm -f "$dest"; echo "encryption failed, removed $dest" >&2; exit 1; fi
  grep -q '^sops:' "$dest" || { rm -f "$dest"; echo "$dest not encrypted, removed" >&2; exit 1; }
}

project_copy() { # <name>
  local name="$1"
  [[ -f "$shared" ]] || { echo "$shared missing: run '$0 init <token-file>' first" >&2; exit 1; }
  [[ -d "apps/$name" ]] || { echo "apps/$name does not exist" >&2; exit 1; }
  sops -d "$shared" | encrypt_to "$name" "apps/$name/ghcr-pull.sops.yaml"
  echo "wrote apps/$name/ghcr-pull.sops.yaml"
}

case "${1:-}" in
  init)
    token_file="${2:?token file}"
    token="$(tr -d '[:space:]' < "$token_file")"
    [[ -n "$token" ]] || { echo "token file is empty" >&2; exit 1; }
    kubectl create secret docker-registry ghcr-pull -n flux-system \
      --docker-server=ghcr.io --docker-username="$owner" --docker-password="$token" \
      --dry-run=client -o yaml | encrypt_to flux-system "$shared"
    echo "wrote $shared"
    grep -q 'ghcr-pull.sops.yaml' infrastructure/configs/kustomization.yaml \
      || sed -i 's|^resources:|resources:\n  - ghcr-pull.sops.yaml|' infrastructure/configs/kustomization.yaml
    for dir in apps/*/; do
      name="$(basename "$dir")"
      [[ "$name" == _template ]] && continue
      project_copy "$name"
    done
    ;;
  project)
    project_copy "${2:?project name}"
    ;;
  *)
    sed -n '2,10p' "$0"; exit 1 ;;
esac

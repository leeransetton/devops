#!/usr/bin/env bash
# Usage: ./scripts/new-project.sh <name> <host> <owner/repo> [port]
# Example: ./scripts/new-project.sh gamadanak gamadanak.com leeransetton/gamadanak 3000
#
# Creates apps/<name>/ from apps/_template, registers it in apps/kustomization.yaml and
# writes its encrypted GHCR pull secret. The image is ghcr.io/<owner/repo> (lowercased),
# which is what docs/app-repo-release.yml pushes.
set -euo pipefail

name="${1:?project name (lowercase letters, digits, dashes)}"
host="${2:?hostname, e.g. example.com}"
repo="${3:?GitHub repo, e.g. leeransetton/myapp}"
port="${4:-8080}"

[[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "invalid name: $name" >&2; exit 1; }
image="ghcr.io/${repo,,}"

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/apps/$name"

if [[ -e "$dest" ]]; then
  echo "apps/$name already exists" >&2
  exit 1
fi

cp -r "$root/apps/_template" "$dest"
for f in "$dest"/*.yaml; do
  sed -i \
    -e "s|__PROJECT__|$name|g" \
    -e "s|__HOST__|$host|g" \
    -e "s|__IMAGE__|$image|g" \
    -e "s|__PORT__|$port|g" \
    "$f"
done

# Register it in apps/kustomization.yaml
kust="$root/apps/kustomization.yaml"
if grep -q '^resources: \[\]' "$kust"; then
  sed -i 's|^resources: \[\]|resources:|' "$kust"
fi
echo "  - $name" >> "$kust"

"$root/scripts/ghcr-pull.sh" project "$name"

echo "Created apps/$name (image $image). Review apps/$name/values.yaml, then commit and push."

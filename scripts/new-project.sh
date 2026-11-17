#!/usr/bin/env bash
# Usage: ./scripts/new-project.sh <name> <host> <image> [port]
# Example: ./scripts/new-project.sh gamadanak gamadanak.com ghcr.io/me/gamadanak 3000
set -euo pipefail

name="${1:?project name (lowercase, dashes ok)}"
host="${2:?hostname, e.g. example.com}"
image="${3:?image without tag, e.g. ghcr.io/owner/repo}"
port="${4:-8080}"

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

echo "Created apps/$name. Review apps/$name/values.yaml, then commit and push."

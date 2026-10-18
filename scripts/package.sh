#!/usr/bin/env bash
# Builds ItemLockForever-<version>.zip with the ItemLockForever folder, for manual installs.
# Releases are packaged by the BigWigs packager (see .pkgmeta).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

version="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
for addon in ItemLockForever; do
	cp -r "$addon" "$staging/$addon"
	sed -i "s/@project-version@/$version/" "$staging/$addon/$addon.toc"
done
output="$ROOT/ItemLockForever-$version.zip"
rm -f "$output"
(cd "$staging" && python3 -m zipfile -c "$output" ItemLockForever)
echo "Built $output"

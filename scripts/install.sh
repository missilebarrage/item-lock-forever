#!/usr/bin/env bash
# Copies the addon folder into the game's AddOns folders and verifies each copy.
# The folders come from $ILF_ADDONS_DIR (one folder) or .tools/addons-path (git-ignored, one
# Interface/AddOns path per line: every game install the addon should be kept up to date in).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

targets=()
if [[ -n "${ILF_ADDONS_DIR:-}" ]]; then
	targets=("$ILF_ADDONS_DIR")
elif [[ -f .tools/addons-path ]]; then
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -n "$line" ]] && targets+=("$line")
	done <.tools/addons-path
fi
if [[ ${#targets[@]} -eq 0 ]]; then
	echo "Set ILF_ADDONS_DIR or write your Interface/AddOns path(s) to .tools/addons-path." >&2
	exit 1
fi

install_into() {
	local target="$1" addon="$2"
	if [[ ! -d "$target" ]]; then
		echo "Not a folder: $target" >&2
		return 1
	fi
	local destination="$target/$addon"
	mkdir -p "$destination"
	# Mirror the folder exactly: copy every file, then remove files that no longer exist.
	(cd "$addon" && find . -type f) | while read -r file; do
		mkdir -p "$destination/$(dirname "$file")"
		cp "$addon/$file" "$destination/$file"
	done
	(cd "$destination" && find . -type f) | while read -r file; do
		[[ -f "$addon/$file" ]] || rm -f "$destination/$file"
	done
	find "$destination" -type d -empty -delete
	# Compare file lists and contents (empty source folders don't matter to the game).
	if ! diff <(cd "$addon" && find . -type f -exec sha256sum {} + | sort -k2) \
		<(cd "$destination" && find . -type f -exec sha256sum {} + | sort -k2) >/dev/null; then
		echo "Installed copy differs from $addon/ in $target" >&2
		return 1
	fi
	echo "Installed $addon to $destination."
}

for target in "${targets[@]}"; do
	for addon in ItemLockForever; do
		install_into "$target" "$addon"
	done
done
echo "A new addon folder needs a full game restart; other changes need /reload."

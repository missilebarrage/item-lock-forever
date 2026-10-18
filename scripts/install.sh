#!/usr/bin/env bash
# Copies the addon folder into the game's AddOns folder and verifies the copy.
# The folder comes from $ILF_ADDONS_DIR or .tools/addons-path (git-ignored, one line).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

target="${ILF_ADDONS_DIR:-}"
if [[ -z "$target" && -f .tools/addons-path ]]; then
	target="$(head -n1 .tools/addons-path)"
fi
if [[ -z "$target" || ! -d "$target" ]]; then
	echo "Set ILF_ADDONS_DIR or write your Interface/AddOns path to .tools/addons-path." >&2
	exit 1
fi

for addon in ItemLockForever; do
	destination="$target/$addon"
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
		echo "Installed copy differs from $addon/" >&2
		exit 1
	fi
	echo "Installed $addon to $destination."
done
echo "A new addon folder needs a full game restart; other changes need /reload."

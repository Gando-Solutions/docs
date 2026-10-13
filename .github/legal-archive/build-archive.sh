#!/usr/bin/env bash
# Builds the archive for one version from a commit of the current checkout.
# Usage: build-archive.sh <tag> <out-dir> [commit]   (tag format: <doc>-YYYY-MM-DD, doc listed in legal-documents.json)
# commit defaults to origin/main. The tag itself does not need to exist yet.
# Env: NODE_PATH + CHROMIUM_PATH for render-pdf.cjs.
set -euo pipefail

tag="$1"; out="$2"; ref="${3:-origin/main}"
here="$(cd "$(dirname "$0")" && pwd)"
map="${LEGAL_MAP:-$here/legal-documents.json}"

[[ "$tag" =~ ^([a-z-]+)-([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || { echo "bad tag format: $tag" >&2; exit 1; }
doc="${BASH_REMATCH[1]}"; date="${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[4]}"
fr_date="${BASH_REMATCH[4]}/${BASH_REMATCH[3]}/${BASH_REMATCH[2]}"
# a document maps to one file, or to {default, "<date>": file} when an earlier version lived in another file
path=$(jq -er --arg d "$doc" --arg date "$date" '.[$d] | if type == "object" then (.[$date] // .default) else . end' "$map") || { echo "unknown document: $doc" >&2; exit 1; }

commit=$(git rev-parse "$ref^{commit}")
git merge-base --is-ancestor "$commit" origin/main || { echo "$commit is not on main" >&2; exit 1; }

dir="$out/$tag"; mkdir -p "$dir"
git show "$commit:$path" > "$dir/source.mdx"

# the effective date written in the text must match the version date (the privacy policy only has a month name, not checked)
if [ "$doc" != "privacy" ] && ! grep -qF "Date d'entrée en vigueur : $fr_date" "$dir/source.mdx"; then
  echo "$path does not say \"Date d'entrée en vigueur : $fr_date\"" >&2; exit 1
fi

# Mintlify components would be dropped by the markdown renderer: fail instead of archiving a partial PDF
if grep -qE '<[A-Z][A-Za-z]*[ />]' "$dir/source.mdx"; then
  echo "unsupported JSX component in $path:" >&2; grep -nE '<[A-Z][A-Za-z]*[ />]' "$dir/source.mdx" >&2; exit 1
fi

sha256=$(sha256sum "$dir/source.mdx" | cut -d' ' -f1)
echo "$sha256  source.mdx" > "$dir/sha256.txt"
(cd "$dir" && node "$here/render-pdf.cjs" .)

jq -n --arg version "$tag" --arg doc "$doc" --arg effectiveFrom "$date" --arg repo "${GITHUB_REPOSITORY:-Gando-Solutions/docs}" \
  --arg path "$path" --arg commit "$commit" --arg sha256 "$sha256" --arg archiveKey "legal/$doc/$tag" \
  '{version:$version, document:$doc, effectiveFrom:$effectiveFrom, repo:$repo, path:$path, commit:$commit, sha256:$sha256, archiveKey:$archiveKey}' \
  | tee "$dir/entry.json"

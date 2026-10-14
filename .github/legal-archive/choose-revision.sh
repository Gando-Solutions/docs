#!/usr/bin/env bash
# Picks the name of the version to publish for one document and effective date.
# Usage: choose-revision.sh <base-tag> <sha256>      (base tag: <doc>-YYYY-MM-DD, without a revision)
# Prints the tag to publish on stdout, the reason on stderr:
#   no version for that date yet             -> the base tag
#   the latest revision has the same hash    -> that revision (a re-run)
#   the latest revision has a different hash -> the next revision (-r2, -r3, ...)
# Existing revisions come from the database when DB_URL is set (it also sees a run that failed before the release),
# otherwise from the git tags of RELEASE_PREFIX (dry run without database access).
set -euo pipefail
# a failing psql or gh inside existing() must stop the script, not read as "no version yet"
shopt -s inherit_errexit

base="$1"; sha="$2"
[[ "$base" =~ ^[a-z-]+-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad base tag: $base" >&2; exit 1; }
prefix="${RELEASE_PREFIX:-}"

existing() {
  if [ -n "${DB_URL:-}" ]; then
    psql "$DB_URL" -v ON_ERROR_STOP=1 -q -t -A -F ' ' \
      -c "SELECT version, sha256 FROM legal_document_versions WHERE version = '$base' OR version LIKE '$base-r%'"
  else
    for t in $(git tag -l "$prefix$base" "$prefix$base-r*"); do
      hash=$(gh release download "$t" -p sha256.txt -O - | cut -d' ' -f1)
      echo "${t#"$prefix"} $hash"
    done
  fi
}

rows=$(existing)
latest_n=0; latest_sha=""
while read -r version stored; do
  [ -n "$version" ] || continue
  if [ "$version" = "$base" ]; then n=1
  elif [[ "$version" =~ ^"$base"-r([0-9]+)$ ]]; then n="${BASH_REMATCH[1]}"
  else continue; fi
  if [ "$n" -gt "$latest_n" ]; then latest_n="$n"; latest_sha="$stored"; fi
done <<<"$rows"

if [ "$latest_n" -eq 0 ]; then echo "no version for this date yet: $base" >&2; echo "$base"; exit 0; fi
latest="$base"; [ "$latest_n" -gt 1 ] && latest="$base-r$latest_n"
if [ "$latest_sha" = "$sha" ]; then echo "same text as $latest: re-run, reusing it" >&2; echo "$latest"; exit 0; fi
echo "text changed since $latest: publishing a new revision" >&2
echo "$base-r$((latest_n + 1))"

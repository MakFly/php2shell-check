#!/usr/bin/env bash
# Rewrite each digest-pinned PHP base image in the given files to the digest
# its tag points to now, only if that image ships the fixed PHP.
# A digest without a tag (img@sha256:...) is mapped to "img:1-phpX.Y" for
# FrankenPHP and "php:X.Y" otherwise, X.Y being the branch of the old image.
# Usage: ./docker-bump.sh FILE...    DRY_RUN=1 to only print the changes.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
status=0

for f in "$@"; do
  for old in $(grep -oE '[a-z0-9./_-]*(php|frankenphp|adminer)[a-z0-9./_-]*(:[A-Za-z0-9._-]+)?@sha256:[0-9a-f]{64}' "$f" | sort -u); do
    name=${old%@*}
    if [[ "$name" != *:* ]]; then
      branch=$(docker run --rm --entrypoint php "$old" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null) \
        || { red "[ERR]  $f : impossible de lire la branche de $old"; status=1; continue; }
      [[ "$name" == *frankenphp ]] && name="$name:1-php$branch" || name="$name:$branch"
      yellow "[INFO] $f : $old sans tag, tag retenu $name (à vérifier)"
    fi
    docker pull -q "$name" >/dev/null || { red "[ERR]  pull $name"; status=1; continue; }
    digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$name" | grep -m1 "^${name%%:*}@" | cut -d@ -f2)
    ver=$(docker run --rm --entrypoint php "$name" -r 'echo PHP_VERSION;')
    if ! verdict "$f : $name" "$ver"; then
      red "       pin conservé : l'image publiée n'est pas encore patchée"; status=1; continue
    fi
    new="$name@$digest"
    [[ "$old" == "$new" ]] && continue
    echo "       $old"; echo "    -> $new"
    [[ -n "${DRY_RUN:-}" ]] || sed -i "s|$old|$new|g" "$f"
  done
done
exit $status

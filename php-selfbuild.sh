#!/usr/bin/env bash
# Stopgap while the official php images are not rebuilt: build a php base
# image from the docker-library Dockerfile, bumped to the fixed release.
# The tarball is checked against the sha256 published by php.net, and the
# Dockerfile still verifies its GPG signature.
# Usage: ./php-selfbuild.sh PHP_VERSION OS VARIANT
#   ./php-selfbuild.sh 8.4.27 trixie zts      -> php-patched:8.4.27-zts-trixie
#   ./php-selfbuild.sh 8.5.12 alpine3.24 cli  -> php-patched:8.5.12-cli-alpine3.24
set -euo pipefail
source "$(dirname "$0")/lib.sh"
php=${1:?PHP_VERSION, ex. 8.4.27}; os=${2:?OS, ex. trixie}; variant=${3:?VARIANT: cli, fpm, zts, apache}
branch=$(cut -d. -f1,2 <<<"$php")
upstream_fixed "$branch" || { red "aucune release $branch corrigée connue"; exit 1; }
ver_ge "$php" "${FIXED[$branch]}" || { red "$php < ${FIXED[$branch]} (version corrigée)"; exit 1; }

here="$(dirname "$(readlink -f "$0")")"
lib="$here/build/docker-library-php"
[[ -d "$lib" ]] || { mkdir -p "$lib" && curl -fsSL https://codeload.github.com/docker-library/php/tar.gz/refs/heads/master | tar -xz -C "$lib" --strip-components=1; }
src="$lib/$branch/$os/$variant"
[[ -f "$src/Dockerfile" ]] || { red "pas de Dockerfile docker-library pour $branch/$os/$variant"; exit 1; }

sha=$(curl -fsS "https://www.php.net/releases/index.php?json&version=$php" | grep -o "\"filename\":\"php-$php.tar.xz\"[^}]*\"sha256\":\"[0-9a-f]\{64\}\"" | grep -oE '[0-9a-f]{64}')
[[ ${#sha} -eq 64 ]] || { red "sha256 de php-$php.tar.xz introuvable sur php.net"; exit 1; }

dst="$here/build/php-$php-$variant-$os"
rm -rf "$dst"; cp -r "$src" "$dst"
sed -i -E \
  -e "s|^ENV PHP_VERSION .*|ENV PHP_VERSION $php|" \
  -e "s|php-[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9]*\.tar\.xz|php-$php.tar.xz|g" \
  -e "s|^ENV PHP_SHA256=.*|ENV PHP_SHA256=\"$sha\"|" "$dst/Dockerfile"
grep -q "PHP_SHA256=\"$sha\"" "$dst/Dockerfile" || { red "réécriture du Dockerfile incomplète"; exit 1; }

tag="php-patched:$php-$variant-$os"
docker buildx build --load --platform linux/amd64 -t "$tag" "$dst"
verdict "$tag" "$(docker run --rm --entrypoint php "$tag" -r 'echo PHP_VERSION;')"
echo "$tag"

#!/usr/bin/env bash
# Stopgap for tonight: build a FrankenPHP runner image on the patched official
# php:X.Y.Z-zts image without waiting for the upstream daily rebuild (cron
# 04:00 UTC). Re-pin the official digest with docker-bump.sh once it is out.
# Usage: ./frankenphp-selfbuild.sh PHP_VERSION [OS] [FRANKENPHP_TAG]
#   ./frankenphp-selfbuild.sh 8.4.27 trixie v1.13.1
#   SHIP_TO=user@node ./frankenphp-selfbuild.sh 8.4.27   (docker load on a remote node)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
php=${1:?PHP_VERSION, ex. 8.4.27}; os=${2:-trixie}; ref=${3:-v1.13.1}
branch=$(cut -d. -f1,2 <<<"$php")
upstream_fixed "$branch" || { red "php.net ne publie pas encore de release $branch corrigée"; exit 1; }
fixed=${FIXED[$branch]}
ver_ge "$php" "$fixed" || { red "$php < $fixed (version corrigée)"; exit 1; }
docker manifest inspect "php:${php}-zts-${os}" >/dev/null \
  || { red "php:${php}-zts-${os} pas encore sur Docker Hub (docker-library), réessayer plus tard"; exit 1; }

src="$(dirname "$(readlink -f "$0")")/build/frankenphp-${ref}"
[[ -d "$src" ]] || git clone --depth 1 --branch "$ref" https://github.com/php/frankenphp "$src"
tag="frankenphp-patched:${ref#v}-php${php}-${os}"
target="runner-php-${php//./-}-${os}"

(cd "$src" && PHP_VERSION="$php" VERSION="${ref#v}" SHA="$(git rev-parse HEAD)" LATEST=false \
  docker buildx bake "$target" --set "${target}.platform=linux/amd64" --set "${target}.tags=${tag}" --load)

got=$(docker run --rm --entrypoint php "$tag" -r 'echo PHP_VERSION;')
verdict "$tag" "$got"
if [[ -n "${SHIP_TO:-}" ]]; then
  docker save "$tag" | ssh "$SHIP_TO" 'sudo -n docker load'
fi
echo "Image locale prête : FROM $tag (à remplacer par le digest officiel dès sa sortie)"

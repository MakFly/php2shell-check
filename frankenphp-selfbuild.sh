#!/usr/bin/env bash
# Stopgap for tonight: build a FrankenPHP runner image on the patched official
# php:X.Y.Z-zts image without waiting for the upstream daily rebuild (cron
# 04:00 UTC). Re-pin the official digest with docker-bump.sh once it is out.
# Usage: ./frankenphp-selfbuild.sh PHP_VERSION [OS] [FRANKENPHP_TAG]
#   ./frankenphp-selfbuild.sh 8.4.27 trixie v1.13.1
#   SHIP_TO=user@node ./frankenphp-selfbuild.sh 8.4.27   (docker load on a remote node)
#   PHP_BASE=php-patched:8.4.27-zts-trixie ./frankenphp-selfbuild.sh 8.4.27
#     (local base from php-selfbuild.sh, when php:X.Y.Z-zts is not on Docker Hub yet)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
php=${1:?PHP_VERSION, ex. 8.4.27}; os=${2:-trixie}; ref=${3:-v1.13.1}
branch=$(cut -d. -f1,2 <<<"$php")
upstream_fixed "$branch" || { red "php.net ne publie pas encore de release $branch corrigée"; exit 1; }
fixed=${FIXED[$branch]}
ver_ge "$php" "$fixed" || { red "$php < $fixed (version corrigée)"; exit 1; }
if [[ -n "${PHP_BASE:-}" ]]; then
  base_ver=$(docker run --rm --entrypoint php "$PHP_BASE" -r 'echo PHP_VERSION;') || { red "image $PHP_BASE introuvable"; exit 1; }
  [[ "$base_ver" == "$php" ]] || { red "$PHP_BASE contient PHP $base_ver, pas $php"; exit 1; }
  base_ctx=(--set "runner-php-${php//./-}-${os}.contexts.php-base=docker-image://$PHP_BASE")
else
  docker manifest inspect "php:${php}-zts-${os}" >/dev/null \
    || { red "php:${php}-zts-${os} pas encore sur Docker Hub : lancer php-selfbuild.sh puis PHP_BASE=..."; exit 1; }
  base_ctx=()
fi

src="$(dirname "$(readlink -f "$0")")/build/frankenphp-${ref}"
[[ -d "$src" ]] || { mkdir -p "$src" && curl -fsSL "https://codeload.github.com/php/frankenphp/tar.gz/refs/tags/$ref" | tar -xz -C "$src" --strip-components=1; }
tag="frankenphp-patched:${ref#v}-php${php}-${os}"
target="runner-php-${php//./-}-${os}"

(cd "$src" && PHP_VERSION="$php" VERSION="${ref#v}" SHA="${ref}" LATEST=false \
  docker buildx bake "$target" --set "${target}.platform=linux/amd64" --set "${target}.tags=${tag}" "${base_ctx[@]}" --load)

got=$(docker run --rm --entrypoint php "$tag" -r 'echo PHP_VERSION;')
verdict "$tag" "$got"
if [[ -n "${SHIP_TO:-}" ]]; then
  docker save "$tag" | ssh "$SHIP_TO" 'sudo -n docker load'
fi
echo "Image locale prête : FROM $tag (à remplacer par le digest officiel dès sa sortie)"

#!/usr/bin/env bash
# Install the php2shell fix on this host once it is published: upgrade the
# distro PHP packages (apt, dnf/yum, apk), restart PHP and web services, list
# the containers to rebuild, then run check.sh.
# Docker images are NOT rebuilt here: see docker-scan.sh and docker-bump.sh.
set -euo pipefail
cd "$(dirname "$0")"
SUDO=$([[ $EUID -eq 0 ]] && echo "" || echo "sudo")

if command -v apt-get >/dev/null; then
  $SUDO apt-get update
  mapfile -t pkgs < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' 2>/dev/null | awk '$1 == "ii" && $2 ~ /^php[0-9.]*-/ {print $2}')
  [[ ${#pkgs[@]} -gt 0 ]] && $SUDO apt-get install --only-upgrade -y "${pkgs[@]}"
elif command -v dnf >/dev/null || command -v yum >/dev/null; then
  pm=$(command -v dnf || command -v yum)
  $SUDO "$pm" -y upgrade 'php*'
elif command -v apk >/dev/null; then
  $SUDO apk update
  mapfile -t pkgs < <(apk info 2>/dev/null | grep -E '^php[0-9]*(-|$)')
  [[ ${#pkgs[@]} -gt 0 ]] && $SUDO apk add --upgrade "${pkgs[@]}"
fi

# A running PHP keeps the old code in memory until it restarts.
if command -v systemctl >/dev/null; then
  for unit in $(systemctl list-units --type=service --no-legend 'php*' 'apache2*' 'httpd*' 'frankenphp*' 2>/dev/null | awk '{print $1}'); do
    $SUDO systemctl restart "$unit" && echo "restart $unit"
  done
elif command -v rc-service >/dev/null; then
  for svc in $(rc-status -a 2>/dev/null | awk '/php-fpm|apache2|frankenphp/ {print $1}'); do
    $SUDO rc-service "$svc" restart
  done
fi

if command -v docker >/dev/null && docker ps >/dev/null 2>&1; then
  echo "== Conteneurs PHP : à reconstruire sur une image patchée (un restart ne suffit pas) =="
  docker ps --format '{{.Names}} {{.Image}}' | while read -r name image; do
    { docker exec "$name" php -v || docker exec "$name" frankenphp php-cli -v; } >/dev/null 2>&1 && echo "  $name ($image)"
  done
fi

./check.sh

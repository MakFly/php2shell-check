#!/usr/bin/env bash
# Report whether each PHP runtime on this host carries the php2shell fix
# (CVE-2026-109618, CVE-2026-109619): distro packages (deb, rpm, apk),
# binaries outside any package (source build, /opt, asdf, Homebrew...) and
# running Docker containers (php and FrankenPHP).
# Exit code: 0 = everything patched, 1 = at least one runtime vulnerable or unknown.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
status=0

check_deb() {
  command -v dpkg-query >/dev/null || return 0
  local pkg ver
  for pkg in $(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php[0-9]*-common' 'php-common' 2>/dev/null | awk '$1 == "ii" && $2 != "php-common" {print $2}'); do
    ver=$(dpkg-query -W -f='${Version}' "$pkg")
    verdict_pkg "deb $pkg" "$ver" "$(apt-get changelog "$pkg" 2>/dev/null | head -400)" || status=1
  done
}

check_rpm() {
  command -v rpm >/dev/null || return 0
  local name ver
  while read -r name ver; do
    verdict_pkg "rpm $name" "$ver" "$(rpm -q --changelog "$name" 2>/dev/null | head -400)" || status=1
  done < <(rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' 'php*-common' 2>/dev/null)
}

check_apk() {
  command -v apk >/dev/null || return 0
  local name ver
  while read -r name ver; do
    verdict_pkg "apk $name" "$ver" "" || status=1
  done < <(apk info -v 2>/dev/null | sed -nE 's/^(php[0-9]*-common)-([0-9].*)$/\1 \2/p')
}

check_binaries() {
  local bin path ver
  for bin in $(compgen -c | grep -E '^(php|php-fpm|php-cgi)[0-9.]*$|^frankenphp$' | sort -u); do
    path=$(command -v "$bin") || continue
    pkg_owned "$path" && continue
    if [[ "$bin" == frankenphp ]]; then
      ver=$("$path" php-cli -r 'echo PHP_VERSION;' 2>/dev/null)
    else
      ver=$("$path" -r 'echo PHP_VERSION;' 2>/dev/null || "$path" -v 2>/dev/null | awk 'NR==1{print $2}')
    fi
    [[ -n "$ver" ]] && { verdict "bin $path" "$ver" || status=1; }
  done
}

check_docker() {
  command -v docker >/dev/null || return 0
  docker ps >/dev/null 2>&1 || { yellow "[??]   docker présent mais socket inaccessible : relancer avec sudo"; status=1; return; }
  local name ver
  while read -r name; do
    ver=$(docker exec "$name" php -r 'echo PHP_VERSION;' 2>/dev/null) ||
      ver=$(docker exec "$name" frankenphp php-cli -r 'echo PHP_VERSION;' 2>/dev/null) || continue
    verdict "docker $name" "$ver" || status=1
  done < <(docker ps --format '{{.Names}}')
}

echo "== php2shell-check : $CVES (release $RELEASE_DATE) =="
check_deb; check_rpm; check_apk; check_binaries; check_docker
exit $status

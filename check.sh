#!/usr/bin/env bash
# Report whether each PHP runtime on this host carries the php2shell fix
# (CVE-2026-109618, CVE-2026-109619): distro packages (deb, rpm, apk),
# binaries outside any package (source build, /opt, asdf, Homebrew...) and
# running Docker containers (php and FrankenPHP).
# Exit code: 0 = everything patched, 1 = at least one runtime vulnerable or unknown.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
status=0
PHP_SERVICES=()

check_deb() {
  command -v dpkg-query >/dev/null || return 0
  local pkg ver
  for pkg in $(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php[0-9]*-common' 'php-common' 2>/dev/null | awk '$1 == "ii" && $2 != "php-common" {print $2}'); do
    ver=$(dpkg-query -W -f='${Version}' "$pkg")
    # The installed package ships its own changelog; apt-get changelog needs the
    # network and returns 404 for fresh security uploads (Ubuntu, 2026-10).
    local cl="/usr/share/doc/$pkg/changelog.Debian.gz" log
    log=$( { [ -r "$cl" ] && zcat "$cl" 2>/dev/null || apt-get changelog "$pkg" 2>/dev/null; } | head -400)
    verdict_pkg "deb $pkg" "$ver" "$log" || status=1
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
    [[ "$name" == *.*.* ]] && PHP_SERVICES+=("${name%%.*}")   # Swarm task: <service>.<slot>.<id>
  done < <(docker ps --format '{{.Names}}')
}

# A package upgrade protects nothing until the PHP processes restart: a running
# process keeps the old binary or libphp mapped, which /proc shows as "(deleted)".
# Long-lived CLI workers (queue:work, schedulers) count too.
check_processes() {
  local pid ppid comm pcomm exe stale=0 fresh=0 unreadable=0
  while read -r pid ppid comm; do
    [[ "$comm" =~ ^(php[0-9.]*|php-fpm[0-9.]*|php-cgi[0-9.]*|apache2|httpd|frankenphp)$ ]] || continue
    pcomm=$(ps -o comm= -p "$ppid" 2>/dev/null)
    [[ "$pcomm" == "$comm" ]] && continue                     # worker of an already listed master
    if ! exe=$(readlink "/proc/$pid/exe" 2>/dev/null); then unreadable=$((unreadable + 1)); continue; fi
    if [[ "$exe" == *" (deleted)" ]] || grep -qE 'php[^ ]* \(deleted\)$' "/proc/$pid/maps" 2>/dev/null; then
      red "[VULN] process $comm (pid $pid) tourne encore sur l'ancien PHP : le redémarrer"; stale=$((stale + 1)); status=1
    else
      fresh=$((fresh + 1))
    fi
  done < <(ps -eo pid=,ppid=,comm=)
  [[ $fresh -gt 0 && $stale -eq 0 ]] && green "[OK]   $fresh process PHP chargent le binaire installé"
  [[ $unreadable -gt 0 ]] && { yellow "[??]   $unreadable process PHP illisibles (/proc) : relancer avec sudo"; status=1; }
}

# Swarm: the fixed image only protects once every running task of a PHP
# service uses it. An update still running, paused or rolled back leaves old
# replicas serving. Only services seen running PHP on this node are checked.
check_swarm() {
  command -v docker >/dev/null || return 0
  [[ $(docker info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}' 2>/dev/null) == "active true" ]] || return 0
  local svc spec state img ok=0
  for svc in $(printf '%s\n' "${PHP_SERVICES[@]}" | sort -u); do
    spec=$(docker service inspect -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$svc")
    state=$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}' "$svc")
    case "$state" in
      updating|paused|rollback_started|rollback_paused|rollback_completed)
        red "[VULN] service $svc : mise à jour $state, l'image voulue ne tourne pas partout"; status=1; continue ;;
    esac
    while read -r img; do
      same_image "$img" "$spec" && continue
      red "[VULN] service $svc : une tâche tourne encore sur $img"; status=1; continue 2
    done < <(docker service ps "$svc" --filter desired-state=running --format '{{.Image}}')
    ok=$((ok + 1))
  done
  [[ $ok -gt 0 ]] && green "[OK]   $ok services Swarm convergés sur leur image"
}

echo "== php2shell-check : $CVES (release $RELEASE_DATE${FIXED_VERSIONS:+, versions corrigées $FIXED_VERSIONS}) =="
check_deb; check_rpm; check_apk; check_binaries; check_processes; check_docker; check_swarm
exit $status
